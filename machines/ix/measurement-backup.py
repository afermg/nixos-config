#!/usr/bin/env python3
"""Publish encrypted, SQLite-consistent Recorder snapshots, never a live DB copy.

Source is read-only. Plaintext exists only in the private runtime directory.
Publishing is append-only, with a ciphertext checksum; remote replication and
restore validation are separate checks, not inferred from local success.
"""
import argparse
from contextlib import closing, nullcontext
import datetime
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import pwd
import sqlite3
import subprocess
import tarfile
import tempfile
import time
from urllib.parse import quote


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def snapshot(source, destination, *, limit_bytes=512 * 1024 * 1024, timeout=90):
    source, destination = Path(source), Path(destination)
    if not source.is_file() or source.is_symlink() or destination.exists() or destination.is_symlink():
        raise ValueError("Source must exist; snapshot must be new")
    deadline = time.monotonic() + timeout
    uri = "file:" + quote(str(source.absolute()), safe="/") + "?mode=ro"
    with closing(sqlite3.connect(uri, uri=True, timeout=5)) as src:
        src.execute("PRAGMA query_only=ON")
        page_size = src.execute("PRAGMA page_size").fetchone()[0]
        if src.execute("PRAGMA page_count").fetchone()[0] * page_size > limit_bytes:
            raise ValueError("Recorder exceeds snapshot size limit")

        def progress(status, remaining, total):
            if total * page_size > limit_bytes or time.monotonic() >= deadline:
                raise TimeoutError("Recorder snapshot exceeded size/time bound")

        with closing(sqlite3.connect(destination)) as dst:
            src.backup(dst, pages=256, progress=progress, sleep=0.05)
            if dst.execute("PRAGMA journal_mode=DELETE").fetchone()[0] != "delete":
                raise RuntimeError("Snapshot is not standalone")
    uri = "file:" + quote(str(destination.absolute()), safe="/") + "?immutable=1"
    with closing(sqlite3.connect(uri, uri=True)) as check:
        if check.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
            raise RuntimeError("Snapshot integrity check failed")
        rows = check.execute("SELECT count(*) FROM states").fetchone()[0]
        if not rows:
            raise ValueError("Refusing an empty Recorder snapshot")
        entities = [r[0] for r in check.execute(
            "SELECT DISTINCT m.entity_id FROM states s "
            "JOIN states_meta m ON m.metadata_id=s.metadata_id ORDER BY m.entity_id"
        )]
        newest = check.execute("SELECT max(last_updated_ts) FROM states").fetchone()[0]
    return {"state_rows": rows, "entities": entities, "newest_state_ts": newest,
            "sqlite_sha256": digest(destination), "sqlite_bytes": destination.stat().st_size,
            "integrity_check": "ok", "method": "SQLite online backup API"}


def encrypt_archive(database, manifest, output, *, age, zstd, recipients):
    if not recipients:
        raise ValueError("At least one encryption recipient is required")
    command = [age]
    for recipient in recipients:
        command.extend(["-r", recipient])
    with (nullcontext(output) if hasattr(output, "fileno") else Path(output).open("xb")) as target:
        compressor = subprocess.Popen([zstd, "-q", "-3", "-T1"], stdin=subprocess.PIPE,
                                      stdout=subprocess.PIPE)
        try:
            encryptor = subprocess.Popen(command, stdin=compressor.stdout, stdout=target)
            compressor.stdout.close()
            try:
                with tarfile.open(fileobj=compressor.stdin, mode="w|") as archive:
                    archive.add(database, arcname="home-assistant_v2.db", recursive=False)
                    data = json.dumps(manifest, indent=2).encode()
                    info = tarfile.TarInfo("manifest.json")
                    info.size, info.mode = len(data), 0o600
                    archive.addfile(info, io.BytesIO(data))
                compressor.stdin.close()
                results = [compressor.wait(timeout=60), encryptor.wait(timeout=60)]
                if results != [0, 0]:
                    raise RuntimeError("Compression/encryption failed")
                target.flush()
                os.fsync(target.fileno())
            finally:
                if encryptor.poll() is None:
                    encryptor.terminate()
                    try:
                        encryptor.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        encryptor.kill()
                        encryptor.wait()
        finally:
            if compressor.poll() is None:
                compressor.terminate()
                try:
                    compressor.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    compressor.kill()
                    compressor.wait()


def anonymous_output(directory):
    """Linux/ext4 unnamed staging: invisible to Syncthing until publication.

    Creating the inode in the destination mount also works when systemd binds
    StateDirectory and ReadWritePaths separately (equal st_dev is insufficient).
    Fail closed rather than falling back to a visible partial file.
    """
    fd = os.open(directory, os.O_TMPFILE | os.O_RDWR | os.O_CLOEXEC, 0o600)
    return os.fdopen(fd, "w+b")


def publish(stream, destination, uid, gid):
    """Atomically name a completed anonymous inode, refusing any overwrite."""
    destination = Path(destination)
    stream.flush()
    os.fchmod(stream.fileno(), 0o600)
    os.fchown(stream.fileno(), uid, gid)
    os.fsync(stream.fileno())
    directory = os.open(destination.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        # dir_fd forces linkat; following our own proc-fd link supports O_TMPFILE
        # publication without requiring CAP_DAC_READ_SEARCH.
        os.link("/proc/self/fd/" + str(stream.fileno()), destination.name,
                dst_dir_fd=directory, follow_symlinks=True)
        os.fsync(directory)
    finally:
        os.close(directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--state", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--owner", required=True)
    parser.add_argument("--age", required=True)
    parser.add_argument("--zstd", required=True)
    parser.add_argument("--recipient", action="append", required=True)
    args = parser.parse_args()
    os.umask(0o077)
    runtime, state, output = map(Path, [args.runtime, args.state, args.output])
    for directory in [runtime, state, output]:
        if not directory.is_dir() or directory.is_symlink():
            raise ValueError("Backup directories must already exist and not be symlinks")
    owner = pwd.getpwnam(args.owner)
    with (state / "backup.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        with tempfile.TemporaryDirectory(prefix="snapshot-", dir=runtime) as temp:
            database = Path(temp) / "recorder.sqlite"
            manifest = snapshot(args.source, database)
            now = datetime.datetime.now(datetime.timezone.utc)
            manifest.update(created_at=now.isoformat(), host="ix", scope="Recorder measurements",
                            source=args.source, replication_verified=False)
            name = "ix-measurements-" + now.strftime("%Y%m%dT%H%M%S%fZ") + ".tar.zst.age"
            with anonymous_output(output) as encrypted, anonymous_output(output) as sidecar:
                encrypt_archive(database, manifest, encrypted, age=args.age,
                                zstd=args.zstd, recipients=args.recipient)
                encrypted.seek(0)
                checksum = hashlib.file_digest(encrypted, "sha256").hexdigest()
                sidecar.write((checksum + "  " + name + "\n").encode())
                publish(encrypted, output / name, owner.pw_uid, owner.pw_gid)
                publish(sidecar, output / (name + ".sha256"), owner.pw_uid, owner.pw_gid)
            print(json.dumps({"archive": str(output / name), "sha256": checksum,
                              "state_rows": manifest["state_rows"],
                              "integrity_check": "ok", "replication_verified": False}))


if __name__ == "__main__":
    main()
