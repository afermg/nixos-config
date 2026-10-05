#!/usr/bin/env python3
"""Archive synchronized external Maildirs into searchable MXroute folders.

Run this after mbsync has downloaded each source account. Messages from every
synchronized folder are flattened into one MXroute folder per account, except
Purdue junk, which goes to native Junk (including already imported copies).
Messages are stored as complete RFC 822 messages, so MXroute can search their subjects and
bodies. Copies are deduplicated by Message-ID. Messages without a Message-ID
receive a deterministic archive-key header so repeated runs remain idempotent.
Persistent import receipts prevent later moves/deletions on MXroute from being
undone by the next import. Initialize receipts with --record-existing BEFORE
first enabling bidirectional sync, and retain the state file across upgrades.
"""

from __future__ import annotations

import argparse
import email.utils
import fcntl
import hashlib
import imaplib
import os
import re
import sqlite3
import ssl
import subprocess
import sys
from dataclasses import dataclass, replace
from email.parser import BytesHeaderParser
from pathlib import Path

DESTINATION_HOST = "witcher.mxrouting.net"
DESTINATION_USER = "alan@quasimorphic.com"
RBW_ITEM_NAME = "Quasimorphic Email"
ARCHIVE_KEY_HEADER = "X-Quasimorphic-Archive-Key"
DEFAULT_MAX_NEW_MESSAGES = 500
DEFAULT_STATE_FILE = (
    Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
    / "mirror-mail"
    / "imports.sqlite3"
)
MXROUTE_MAILDIR = Path.home() / ".mail" / "quasimorphic"


@dataclass(frozen=True)
class MirrorConfig:
    name: str
    label: str
    source_roots: tuple[Path, ...]
    destination_folder: str
    route_junk: bool = False


MIRRORS = {
    "purdue": MirrorConfig(
        name="purdue",
        label="Purdue",
        source_roots=(Path.home() / ".mail" / "purdue",),
        destination_folder="INBOX.Purdue",
        route_junk=True,
    ),
    "broad": MirrorConfig(
        name="broad",
        label="Broad",
        source_roots=(
            Path.home() / ".mail" / "broad",
            Path.home() / ".cache" / "mirror-mail" / "broad",
        ),
        destination_folder="INBOX.Broad-Archive",
    ),
    "broad-spam": MirrorConfig(
        name="broad-spam",
        label="Broad spam",
        source_roots=(Path.home() / ".mail" / "broad" / "[Gmail]" / "Spam",),
        destination_folder="Junk",
    ),
}


@dataclass(frozen=True)
class Candidate:
    path: Path
    size: int
    key: str
    message_id: str | None
    junk: bool = False


@dataclass(frozen=True)
class MirrorResult:
    scanned: int
    unique: int
    duplicates: int
    already_archived: int
    appended: int
    deferred: int
    previously_imported: int
    errors: tuple[tuple[Path, str], ...]
    junk_appended: int = 0
    moved_to_junk: int = 0


class ImportHistory:
    """Durable, per-destination receipts; serialize importers on this host."""

    def __init__(self, path: Path):
        self.path = path
        self.lock = None
        self.db = None

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.lock = os.fdopen(
            os.open(str(self.path) + ".lock", os.O_CREAT | os.O_RDWR, 0o600), "a"
        )
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fd = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o600)
            os.close(fd)
            self.db = sqlite3.connect(self.path)
            self.db.executescript("""
                CREATE TABLE IF NOT EXISTS imports (
                    destination TEXT NOT NULL, message_key TEXT NOT NULL,
                    PRIMARY KEY (destination, message_key));
                CREATE TABLE IF NOT EXISTS initialized (
                    destination TEXT PRIMARY KEY);
            """)
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, *_args):
        if self.db is not None:
            self.db.close()
        if self.lock is not None:
            self.lock.close()

    @staticmethod
    def scope(config: MirrorConfig) -> str:
        return f"{DESTINATION_HOST}/{DESTINATION_USER}/{config.destination_folder}"

    def require_initialized(self, config: MirrorConfig) -> None:
        if (
            self.db.execute(
                "SELECT 1 FROM initialized WHERE destination = ?", (self.scope(config),)
            ).fetchone()
            is None
        ):
            raise RuntimeError(
                f"{config.label} import history is uninitialized; run --record-existing before syncing"
            )

    def keys(self, config: MirrorConfig) -> set[str]:
        self.require_initialized(config)
        return {
            row[0]
            for row in self.db.execute(
                "SELECT message_key FROM imports WHERE destination = ?",
                (self.scope(config),),
            )
        }

    def remember(
        self, config: MirrorConfig, keys: set[str], *, initialize: bool = False
    ) -> None:
        with self.db:
            self.db.executemany(
                "INSERT OR IGNORE INTO imports VALUES (?, ?)",
                ((self.scope(config), key) for key in keys),
            )
            if initialize:
                self.db.execute(
                    "INSERT OR IGNORE INTO initialized VALUES (?)",
                    (self.scope(config),),
                )


def get_password() -> str:
    """Read a private runtime file when configured, otherwise use the vault."""
    if password_file := os.environ.get("MIRROR_MAIL_PASSWORD_FILE"):
        password = Path(password_file).read_text().strip()
        if not password:
            raise RuntimeError("The configured mail password file is empty")
        return password
    result = subprocess.run(
        ["rbw", "get", RBW_ITEM_NAME],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def normalize_message_id(value: str | None) -> str | None:
    if not value:
        return None
    normalized = value.strip().strip("<>").strip()
    return f"mid:{normalized}" if normalized else None


def archive_key(raw: bytes, message_id: str | None) -> str:
    return (
        normalize_message_id(message_id) or f"sha256:{hashlib.sha256(raw).hexdigest()}"
    )


def iter_message_paths(source_roots: tuple[Path, ...]) -> list[Path]:
    paths: list[Path] = []
    for source_root in source_roots:
        for leaf_name in ("cur", "new"):
            for leaf in source_root.rglob(leaf_name):
                if not leaf.is_dir():
                    continue
                for path in leaf.iterdir():
                    if path.is_file() and not path.name.startswith("."):
                        paths.append(path)
    return paths


def local_candidates(
    source_roots: tuple[Path, ...],
) -> tuple[dict[str, Candidate], int]:
    """Return one largest local copy for each stable message key."""
    candidates: dict[str, Candidate] = {}
    duplicate_count = 0
    parser = BytesHeaderParser()

    for path in iter_message_paths(source_roots):
        raw = path.read_bytes()
        headers = parser.parsebytes(raw, headersonly=True)
        raw_message_id = headers.get("Message-ID")
        message_id = raw_message_id if normalize_message_id(raw_message_id) else None
        key = archive_key(raw, message_id)
        junk_folder = any(
            "Junk Email" in (root.name, *path.relative_to(root).parts[:-2])
            for root in source_roots
            if path.is_relative_to(root)
        )
        # Folder membership is authoritative. Spam headers can be stale after
        # rescue from Junk and have false positives in forwarded archive copies.
        candidate = Candidate(path, len(raw), key, message_id, junk_folder)
        previous = candidates.get(key)
        if previous is None:
            candidates[key] = candidate
        else:
            duplicate_count += 1
            # A junk copy wins classification even if a larger normal copy exists.
            largest = candidate if candidate.size > previous.size else previous
            candidates[key] = replace(largest, junk=candidate.junk or previous.junk)

    return candidates, duplicate_count


def ensure_destination(connection: imaplib.IMAP4_SSL, destination_folder: str) -> None:
    status, _ = connection.select(f'"{destination_folder}"', readonly=True)
    if status == "OK":
        return
    status, data = connection.create(f'"{destination_folder}"')
    response = b" ".join(item for item in data or [] if isinstance(item, bytes))
    if status != "OK" and b"exist" not in response.lower():
        raise RuntimeError(f"Cannot create {destination_folder}: {status} {response!r}")
    status, data = connection.select(f'"{destination_folder}"', readonly=True)
    if status != "OK":
        raise RuntimeError(f"Cannot select {destination_folder}: {status} {data!r}")


def remote_keys(connection: imaplib.IMAP4_SSL, destination_folder: str) -> set[str]:
    """Fetch stable keys already present in the selected archive folder."""
    status, data = connection.uid("search", None, "ALL")
    if status != "OK":
        raise RuntimeError(f"Cannot search {destination_folder}: {status} {data!r}")
    uids = (data[0] or b"").split()
    keys: set[str] = set()
    parser = BytesHeaderParser()

    for start in range(0, len(uids), 500):
        batch = b",".join(uids[start : start + 500]).decode("ascii")
        status, responses = connection.uid(
            "fetch",
            batch,
            f"(BODY.PEEK[HEADER.FIELDS (MESSAGE-ID {ARCHIVE_KEY_HEADER})])",
        )
        if status != "OK":
            raise RuntimeError(
                f"Cannot fetch destination headers from {destination_folder}: {status}"
            )
        for response in responses or []:
            if not isinstance(response, tuple) or len(response) < 2:
                continue
            headers = parser.parsebytes(response[1], headersonly=True)
            message_key = normalize_message_id(headers.get("Message-ID"))
            fallback_key = headers.get(ARCHIVE_KEY_HEADER)
            if message_key:
                keys.add(message_key)
            if fallback_key:
                keys.add(fallback_key.strip().lower())
    return keys


def local_receipt_keys(roots: tuple[Path, ...]) -> set[str]:
    """Include locally retained/deletion-marked copies when seeding receipts."""
    keys: set[str] = set()
    parser = BytesHeaderParser()
    for path in iter_message_paths(roots):
        with path.open("rb") as handle:
            lines = []
            for line in handle:
                lines.append(line)
                if line in (b"\n", b"\r\n"):
                    break
        headers = parser.parsebytes(b"".join(lines), headersonly=True)
        key = normalize_message_id(headers.get("Message-ID"))
        fallback = headers.get(ARCHIVE_KEY_HEADER)
        keys.add(
            key
            or (
                fallback.strip().lower()
                if fallback
                else archive_key(path.read_bytes(), None)
            )
        )
    return keys


def record_existing(
    connection: imaplib.IMAP4_SSL, config: MirrorConfig, history: ImportHistory
) -> int:
    """Seed before sync: include existing imports plus already moved/deleted mail."""
    ensure_destination(connection, config.destination_folder)
    keys = remote_keys(connection, config.destination_folder)
    parts = config.destination_folder.split(".")
    if parts[0] == "INBOX":
        parts[0] = "Inbox"
    roots = tuple(
        {
            MXROUTE_MAILDIR.joinpath(*parts),
            MXROUTE_MAILDIR / "Junk",
            MXROUTE_MAILDIR / "Trash",
        }
    )
    keys.update(local_receipt_keys(roots))
    # Include server-side moves not downloaded by the last local sync yet.
    for folder in {"Junk", "Trash"} - {config.destination_folder}:
        status, data = connection.select(f'"{folder}"', readonly=True)
        if status != "OK":
            raise RuntimeError(f"Cannot seed receipts from {folder}: {status} {data!r}")
        keys.update(remote_keys(connection, folder))
    history.remember(config, keys, initialize=True)
    return len(keys)


def add_fallback_key(raw: bytes, key: str) -> bytes:
    """Add a deduplication header only when the source lacks Message-ID."""
    match = re.search(rb"\r?\n\r?\n", raw)
    if not match:
        return f"{ARCHIVE_KEY_HEADER}: {key}\r\n\r\n".encode("ascii") + raw
    newline = b"\r\n" if match.group() == b"\r\n\r\n" else b"\n"
    header = f"{ARCHIVE_KEY_HEADER}: {key}".encode("ascii")
    return (
        raw[: match.start()] + newline + header + newline + newline + raw[match.end() :]
    )


def imap_flags(path: Path) -> str | None:
    match = re.search(r":2,([A-Za-z]*)$", path.name)
    source_flags = set(match.group(1)) if match else set()
    flags = []
    for local, remote in (
        ("S", r"\Seen"),
        ("F", r"\Flagged"),
        ("D", r"\Draft"),
        ("R", r"\Answered"),
    ):
        if local in source_flags:
            flags.append(remote)
    return f"({' '.join(flags)})" if flags else None


def internal_date(raw: bytes, path: Path) -> str:
    headers = BytesHeaderParser().parsebytes(raw, headersonly=True)
    try:
        parsed = email.utils.parsedate_to_datetime(headers.get("Date"))
        if parsed is not None:
            return imaplib.Time2Internaldate(parsed.timestamp())
    except (TypeError, ValueError, OverflowError):
        pass
    return imaplib.Time2Internaldate(path.stat().st_mtime)


def move_purdue_junk(
    connection: imaplib.IMAP4_SSL,
    config: MirrorConfig,
    junk_config: MirrorConfig,
    junk_keys: set[str],
    history: ImportHistory,
) -> int:
    """Move archive copies of messages currently in Purdue's Junk Email.

    Exclude pending deletions and leave Trash/other user-filed folders alone.
    Do not classify by stale spam headers, sender, subject, or fuzzy matches.
    """
    if not junk_keys:
        return 0
    ensure_destination(connection, config.destination_folder)
    status, data = connection.uid("search", None, "UNDELETED")
    if status != "OK":
        raise RuntimeError(
            f"Cannot search {config.destination_folder}: {status} {data!r}"
        )
    uids = (data[0] or b"").split()
    moves: dict[str, set[str]] = {}
    parser = BytesHeaderParser()
    for start in range(0, len(uids), 500):
        batch = b",".join(uids[start : start + 500]).decode("ascii")
        status, responses = connection.uid(
            "fetch",
            batch,
            f"(UID BODY.PEEK[HEADER.FIELDS (MESSAGE-ID {ARCHIVE_KEY_HEADER})])",
        )
        if status != "OK":
            raise RuntimeError(f"Cannot inspect {config.destination_folder}: {status}")
        for response in responses or []:
            if not isinstance(response, tuple):
                continue
            headers = parser.parsebytes(response[1], headersonly=True)
            key = normalize_message_id(headers.get("Message-ID"))
            fallback = headers.get(ARCHIVE_KEY_HEADER)
            keys = {key} if key else set()
            if fallback:
                keys.add(fallback.strip().lower())
            if not keys & junk_keys:
                continue
            uid = re.search(rb"\bUID (\d+)\b", response[0])
            if uid is None:
                raise RuntimeError("Missing UID in junk header response")
            moves[uid[1].decode("ascii")] = keys

    if moves:
        # imaplib's cached capabilities can predate LOGIN; refresh explicitly.
        status, capabilities = connection.capability()
        if status != "OK" or b"MOVE" not in b" ".join(capabilities).split():
            raise RuntimeError(
                "Server lacks UID MOVE; refusing unsafe COPY/EXPUNGE fallback"
            )
        ensure_destination(connection, "Junk")
        status, data = connection.select(
            f'"{config.destination_folder}"', readonly=False
        )
        if status != "OK":
            raise RuntimeError(
                f"Cannot select archive for junk moves: {status} {data!r}"
            )
        pending = sorted(moves, key=int)
        for start in range(0, len(pending), 100):
            batch = pending[start : start + 100]
            keys = set().union(*(moves[uid] for uid in batch))
            # Record archive presence before the move, so interrupted runs cannot
            # resurrect a copy subsequently removed by the user from Junk.
            history.remember(config, keys)
            status, data = connection.uid("move", ",".join(batch), '"Junk"')
            if status != "OK":
                raise RuntimeError(f"Cannot move Purdue junk: {status} {data!r}")
            history.remember(junk_config, keys)
    return len(moves)


def mirror_account(
    connection: imaplib.IMAP4_SSL,
    config: MirrorConfig,
    max_new_messages: int,
    history: ImportHistory,
) -> MirrorResult:
    history.require_initialized(config)
    missing_roots = [root for root in config.source_roots if not root.is_dir()]
    if missing_roots:
        missing = ", ".join(str(root) for root in missing_roots)
        raise RuntimeError(f"{config.label} source Maildir does not exist: {missing}")

    candidates, duplicate_count = local_candidates(config.source_roots)
    if not config.route_junk:
        return mirror_candidates(
            connection, config, candidates, duplicate_count, max_new_messages, history
        )

    junk_config = replace(
        config,
        label=f"{config.label} junk",
        destination_folder="Junk",
        route_junk=False,
    )
    history.require_initialized(junk_config)
    junk_keys = {key for key, candidate in candidates.items() if candidate.junk}
    # Include deletion-marked archive copies before routing, so an unrecorded
    # pending deletion cannot be mistaken for a new junk import.
    ensure_destination(connection, config.destination_folder)
    history.remember(config, remote_keys(connection, config.destination_folder))
    moved = move_purdue_junk(connection, config, junk_config, junk_keys, history)
    junk = {key: candidate for key, candidate in candidates.items() if key in junk_keys}
    normal = {
        key: candidate for key, candidate in candidates.items() if key not in junk_keys
    }
    # A former archive import that is now absent was already moved/deleted by
    # the user. Changing its classification must not recreate it in Junk.
    history.remember(junk_config, history.keys(config) & junk_keys)
    junk_result = mirror_candidates(
        connection, junk_config, junk, 0, max_new_messages, history
    )
    # Never re-import junk into the archive, even if it later leaves source Junk.
    history.remember(config, history.keys(junk_config) & junk_keys)
    result = mirror_candidates(
        connection, config, normal, duplicate_count, max_new_messages, history
    )
    return replace(
        result,
        scanned=result.scanned + junk_result.scanned,
        unique=result.unique + junk_result.unique,
        already_archived=result.already_archived + junk_result.already_archived,
        previously_imported=result.previously_imported
        + junk_result.previously_imported,
        appended=result.appended + junk_result.appended,
        deferred=result.deferred + junk_result.deferred,
        errors=result.errors + junk_result.errors,
        junk_appended=junk_result.appended,
        moved_to_junk=moved,
    )


def mirror_candidates(
    connection: imaplib.IMAP4_SSL,
    config: MirrorConfig,
    candidates: dict[str, Candidate],
    duplicate_count: int,
    max_new_messages: int,
    history: ImportHistory,
) -> MirrorResult:
    imported = history.keys(config)
    ensure_destination(connection, config.destination_folder)
    existing = remote_keys(connection, config.destination_folder)
    history.remember(config, existing)
    known = existing | imported
    pending = sorted(
        (item for key, item in candidates.items() if key not in known),
        key=lambda item: str(item.path),
    )
    selected = pending[:max_new_messages]

    appended = 0
    errors: list[tuple[Path, str]] = []
    for candidate in selected:
        try:
            raw = candidate.path.read_bytes()
            if candidate.message_id is None:
                raw = add_fallback_key(raw, candidate.key)
            status, data = connection.append(
                f'"{config.destination_folder}"',
                imap_flags(candidate.path),
                internal_date(raw, candidate.path),
                raw,
            )
            if status != "OK":
                errors.append((candidate.path, repr(data)[:200]))
            else:
                # Commit before exposing the import to the next local sync.
                # On uncertain APPEND failures, the next remote scan deduplicates.
                history.remember(config, {candidate.key})
                appended += 1
                if appended % 250 == 0:
                    print(
                        f"{config.label} mirror progress: "
                        f"appended={appended}/{len(selected)}",
                        flush=True,
                    )
        except (OSError, imaplib.IMAP4.error) as error:
            errors.append((candidate.path, str(error)[:200]))

    return MirrorResult(
        scanned=len(candidates) + duplicate_count,
        unique=len(candidates),
        duplicates=duplicate_count,
        already_archived=len(candidates.keys() & existing),
        appended=appended,
        deferred=len(pending) - len(selected),
        previously_imported=len((candidates.keys() & imported) - existing),
        errors=tuple(errors),
    )


def print_result(config: MirrorConfig, result: MirrorResult) -> None:
    print(
        f"{config.label} mirror: "
        f"scanned={result.scanned} "
        f"unique={result.unique} duplicates={result.duplicates} "
        f"already_archived={result.already_archived} "
        f"previously_imported={result.previously_imported} "
        f"appended={result.appended} junk_appended={result.junk_appended} "
        f"moved_to_junk={result.moved_to_junk} deferred={result.deferred} "
        f"errors={len(result.errors)}"
    )
    for path, message in result.errors[:10]:
        print(f"  ERROR {path}: {message}", file=sys.stderr)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "accounts",
        nargs="+",
        choices=tuple(MIRRORS),
        help="source account(s) to archive into MXroute",
    )
    parser.add_argument(
        "--max-new-messages",
        type=int,
        default=DEFAULT_MAX_NEW_MESSAGES,
        metavar="COUNT",
        help=(
            "maximum messages to append per destination and run "
            f"(default: {DEFAULT_MAX_NEW_MESSAGES})"
        ),
    )
    parser.add_argument(
        "--state-file",
        type=Path,
        default=DEFAULT_STATE_FILE,
        help="persistent import receipts (keep this file to honor deletions)",
    )
    parser.add_argument(
        "--record-existing",
        action="store_true",
        help="initialize/update receipts from existing copies without uploading mail",
    )
    args = parser.parse_args(argv)
    if args.max_new_messages < 1:
        parser.error("--max-new-messages must be at least 1")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    password = get_password()
    context = ssl.create_default_context()
    exit_status = 0

    with (
        ImportHistory(args.state_file) as history,
        imaplib.IMAP4_SSL(DESTINATION_HOST, 993, ssl_context=context) as connection,
    ):
        connection.login(DESTINATION_USER, password)
        for account in args.accounts:
            config = MIRRORS[account]
            try:
                if args.record_existing:
                    count = record_existing(connection, config, history)
                    if config.route_junk:
                        record_existing(
                            connection,
                            replace(
                                config, destination_folder="Junk", route_junk=False
                            ),
                            history,
                        )
                    print(
                        f"{config.label} import receipts initialized: keys={count}",
                        flush=True,
                    )
                    continue
                result = mirror_account(
                    connection,
                    config,
                    max_new_messages=args.max_new_messages,
                    history=history,
                )
            except (OSError, RuntimeError, sqlite3.Error, imaplib.IMAP4.error) as error:
                print(f"{config.label} mirror failed: {error}", file=sys.stderr)
                exit_status = 1
                continue
            print_result(config, result)
            if result.errors:
                exit_status = 1

        # The context manager logs out without expunging any messages.

    return exit_status


if __name__ == "__main__":
    raise SystemExit(main())
