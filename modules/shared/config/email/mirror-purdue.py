#!/usr/bin/env python3
"""Mirror the local Purdue Maildir into mxroute's INBOX.Purdue folder.

Run this after ``mbsync purdue``. Messages from every synchronized Purdue
folder are flattened into one durable archive, deduplicated by Message-ID.
Messages without a Message-ID receive a deterministic archive-key header so
repeated runs remain idempotent.
"""

from __future__ import annotations

import email.utils
import hashlib
import imaplib
import re
import ssl
import subprocess
import sys
from dataclasses import dataclass
from email.parser import BytesHeaderParser
from pathlib import Path

SOURCE_ROOT = Path.home() / ".mail" / "purdue"
DESTINATION_HOST = "witcher.mxrouting.net"
DESTINATION_USER = "alan@quasimorphic.com"
DESTINATION_FOLDER = "INBOX.Purdue"
PASSWORD_ENTRY = "Quasimorphic Email"
ARCHIVE_KEY_HEADER = "X-Quasimorphic-Archive-Key"


@dataclass(frozen=True)
class Candidate:
    path: Path
    folder: str
    size: int
    key: str
    message_id: str | None


def get_password() -> str:
    """Read the mxroute password without putting it in configuration files."""
    result = subprocess.run(
        ["rbw", "get", PASSWORD_ENTRY],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def normalize_message_id(value: str | None) -> str | None:
    if not value:
        return None
    normalized = value.strip().strip("<>")
    return f"mid:{normalized}" if normalized else None


def archive_key(raw: bytes, message_id: str | None) -> str:
    return normalize_message_id(message_id) or f"sha256:{hashlib.sha256(raw).hexdigest()}"


def iter_message_paths() -> list[tuple[Path, str]]:
    paths: list[tuple[Path, str]] = []
    for leaf_name in ("cur", "new"):
        for leaf in SOURCE_ROOT.rglob(leaf_name):
            if not leaf.is_dir():
                continue
            folder = leaf.parent.relative_to(SOURCE_ROOT).as_posix()
            for path in leaf.iterdir():
                if path.is_file() and not path.name.startswith("."):
                    paths.append((path, folder))
    return paths


def local_candidates() -> tuple[dict[str, Candidate], int]:
    """Return one largest local copy for each stable message key."""
    candidates: dict[str, Candidate] = {}
    duplicate_count = 0
    parser = BytesHeaderParser()

    for path, folder in iter_message_paths():
        raw = path.read_bytes()
        headers = parser.parsebytes(raw, headersonly=True)
        message_id = headers.get("Message-ID")
        key = archive_key(raw, message_id)
        candidate = Candidate(path, folder, len(raw), key, message_id)
        previous = candidates.get(key)
        if previous is None or candidate.size > previous.size:
            if previous is not None:
                duplicate_count += 1
            candidates[key] = candidate
        else:
            duplicate_count += 1

    return candidates, duplicate_count


def ensure_destination(connection: imaplib.IMAP4_SSL) -> None:
    status, _ = connection.select(f'"{DESTINATION_FOLDER}"', readonly=True)
    if status == "OK":
        return
    status, data = connection.create(f'"{DESTINATION_FOLDER}"')
    response = b" ".join(item for item in data or [] if isinstance(item, bytes))
    if status != "OK" and b"exist" not in response.lower():
        raise RuntimeError(f"Cannot create {DESTINATION_FOLDER}: {status} {response!r}")
    status, data = connection.select(f'"{DESTINATION_FOLDER}"', readonly=True)
    if status != "OK":
        raise RuntimeError(f"Cannot select {DESTINATION_FOLDER}: {status} {data!r}")


def remote_keys(connection: imaplib.IMAP4_SSL) -> set[str]:
    """Fetch stable keys already present in the destination archive."""
    status, data = connection.uid("search", None, "ALL")
    if status != "OK":
        raise RuntimeError(f"Cannot search {DESTINATION_FOLDER}: {status} {data!r}")
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
            raise RuntimeError(f"Cannot fetch destination headers: {status}")
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


def add_fallback_key(raw: bytes, key: str) -> bytes:
    """Add a deduplication header only when the source lacks Message-ID."""
    match = re.search(rb"\r?\n\r?\n", raw)
    if not match:
        return f"{ARCHIVE_KEY_HEADER}: {key}\r\n\r\n".encode("ascii") + raw
    newline = b"\r\n" if match.group() == b"\r\n\r\n" else b"\n"
    header = f"{ARCHIVE_KEY_HEADER}: {key}".encode("ascii")
    return raw[: match.start()] + newline + header + newline + newline + raw[match.end() :]


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


def main() -> int:
    if not SOURCE_ROOT.is_dir():
        print(f"Purdue source Maildir does not exist: {SOURCE_ROOT}", file=sys.stderr)
        return 2

    candidates, duplicate_count = local_candidates()
    password = get_password()
    context = ssl.create_default_context()

    with imaplib.IMAP4_SSL(DESTINATION_HOST, 993, ssl_context=context) as connection:
        connection.login(DESTINATION_USER, password)
        ensure_destination(connection)
        existing = remote_keys(connection)
        pending = [item for key, item in candidates.items() if key not in existing]

        appended = 0
        errors: list[tuple[Path, str]] = []
        for candidate in sorted(pending, key=lambda item: str(item.path)):
            try:
                raw = candidate.path.read_bytes()
                if candidate.message_id is None:
                    raw = add_fallback_key(raw, candidate.key)
                status, data = connection.append(
                    f'"{DESTINATION_FOLDER}"',
                    imap_flags(candidate.path),
                    internal_date(raw, candidate.path),
                    raw,
                )
                if status != "OK":
                    errors.append((candidate.path, repr(data)[:200]))
                else:
                    appended += 1
            except (OSError, imaplib.IMAP4.error) as error:
                errors.append((candidate.path, str(error)[:200]))

        try:
            connection.close()
        except imaplib.IMAP4.error:
            pass

    print(
        "Purdue mirror: "
        f"scanned={len(candidates) + duplicate_count} "
        f"unique={len(candidates)} duplicates={duplicate_count} "
        f"already_archived={len(candidates) - len(pending)} "
        f"appended={appended} errors={len(errors)}"
    )
    for path, message in errors[:10]:
        print(f"  ERROR {path}: {message}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
