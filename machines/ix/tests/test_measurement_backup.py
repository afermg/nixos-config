"""No HA instance or physical events: local SQLite/encryption fixtures only."""
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("measurement_backup", Path(__file__).parents[1] / "measurement-backup.py")
backup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backup)
AGE = os.environ.get("IX_TEST_AGE", shutil.which("age"))
ZSTD = shutil.which("zstd")


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / "live DB?one.db"
        self.destination = self.root / "snapshot.db"
        self.writer = sqlite3.connect(self.source)
        self.addCleanup(self.writer.close)
        self.writer.executescript("""
            PRAGMA journal_mode=WAL;
            PRAGMA wal_autocheckpoint=0;
            CREATE TABLE states_meta(metadata_id INTEGER PRIMARY KEY, entity_id TEXT);
            CREATE TABLE states(state_id INTEGER PRIMARY KEY, metadata_id INTEGER, last_updated_ts REAL);
            INSERT INTO states_meta VALUES(1, 'sensor.fixture');
            INSERT INTO states VALUES(1, 1, 123456.0);
        """)
        self.writer.commit()

    def test_wal_data_is_in_standalone_snapshot_without_changing_source(self):
        before = [backup.digest(self.source), backup.digest(str(self.source) + "-wal")]
        report = backup.snapshot(self.source, self.destination)
        self.assertEqual(report["state_rows"], 1)
        self.assertEqual(report["entities"], ["sensor.fixture"])
        self.assertEqual(report["integrity_check"], "ok")
        self.assertEqual(before, [backup.digest(self.source), backup.digest(str(self.source) + "-wal")])
        self.assertFalse(Path(str(self.destination) + "-wal").exists())
        with sqlite3.connect("file:" + str(self.destination) + "?immutable=1", uri=True) as db:
            self.assertEqual(db.execute("SELECT last_updated_ts FROM states").fetchone(), (123456.0,))

    def test_size_limit_does_not_create_snapshot(self):
        with self.assertRaises(ValueError):
            backup.snapshot(self.source, self.destination, limit_bytes=1)
        self.assertFalse(self.destination.exists())

    def test_deadline_is_enforced(self):
        with self.assertRaises(TimeoutError):
            backup.snapshot(self.source, self.destination, timeout=-1)

    def test_missing_source_is_not_created(self):
        source = self.root / "missing.db"
        with self.assertRaises(ValueError):
            backup.snapshot(source, self.destination)
        self.assertFalse(source.exists())

    def test_existing_destination_is_never_overwritten(self):
        self.destination.write_bytes(b"preserve")
        with self.assertRaises(ValueError):
            backup.snapshot(self.source, self.destination)
        self.assertEqual(self.destination.read_bytes(), b"preserve")

    def test_symlinks_are_rejected(self):
        link = self.root / "source-link"
        link.symlink_to(self.source)
        with self.assertRaises(ValueError):
            backup.snapshot(link, self.destination)
        self.destination.symlink_to(self.root / "absent")
        with self.assertRaises(ValueError):
            backup.snapshot(self.source, self.destination)

    def test_empty_recorder_is_rejected(self):
        self.writer.execute("DELETE FROM states")
        self.writer.commit()
        with self.assertRaises(ValueError):
            backup.snapshot(self.source, self.destination)

    def test_malformed_source_is_rejected(self):
        bad = self.root / "bad.db"
        bad.write_bytes(b"not a database" * 1000)
        with self.assertRaises(sqlite3.DatabaseError):
            backup.snapshot(bad, self.destination)

    def test_publish_is_append_only_and_staging_is_invisible(self):
        target = self.root / "published"
        before = set(self.root.iterdir())
        with backup.anonymous_output(self.root) as staged:
            staged.write(b"ciphertext")
            self.assertEqual(set(self.root.iterdir()), before)
            backup.publish(staged, target, os.getuid(), os.getgid())
        self.assertEqual(target.read_bytes(), b"ciphertext")
        self.assertEqual(target.stat().st_mode & 0o777, 0o600)
        with backup.anonymous_output(self.root) as staged:
            staged.write(b"different")
            with self.assertRaises(FileExistsError):
                backup.publish(staged, target, os.getuid(), os.getgid())
        self.assertEqual(target.read_bytes(), b"ciphertext")

    def test_failed_anonymous_staging_leaves_no_partial_files(self):
        before = set(self.root.iterdir())
        with backup.anonymous_output(self.root) as staged:
            staged.write(b"incomplete ciphertext")
        self.assertEqual(set(self.root.iterdir()), before)

    def test_encryption_requires_recipient_before_writing(self):
        out = self.root / "encrypted"
        with self.assertRaises(ValueError):
            backup.encrypt_archive(self.source, {}, out, age="missing", zstd="missing", recipients=[])
        self.assertFalse(out.exists())

    @unittest.skipUnless(AGE and ZSTD, "age and zstd required for real encryption roundtrip")
    def test_real_encryption_roundtrip(self):
        key = self.root / "key"
        subprocess.run([str(Path(AGE).with_name("age-keygen")), "-o", str(key)],
                       check=True, capture_output=True)
        recipient = subprocess.check_output([str(Path(AGE).with_name("age-keygen")), "-y", str(key)], text=True).strip()
        manifest = backup.snapshot(self.source, self.destination)
        encrypted = self.root / "snapshot.tar.zst.age"
        backup.encrypt_archive(self.destination, manifest, encrypted, age=AGE, zstd=ZSTD, recipients=[recipient])
        packed = subprocess.check_output([AGE, "-d", "-i", str(key), str(encrypted)])
        data = subprocess.run([ZSTD, "-q", "-d", "-c"], input=packed, capture_output=True, check=True).stdout
        with tarfile.open(fileobj=io.BytesIO(data)) as archive:
            self.assertEqual(archive.getnames(), ["home-assistant_v2.db", "manifest.json"])
            self.assertEqual(archive.extractfile("home-assistant_v2.db").read(), self.destination.read_bytes())
            self.assertEqual(json.load(archive.extractfile("manifest.json")), manifest)
        self.assertNotIn(b"SQLite format 3", encrypted.read_bytes())

    @unittest.skipUnless(ZSTD, "zstd required")
    def test_failed_encryptor_does_not_publish(self):
        for name in ["runtime", "staging", "output"]:
            (self.root / name).mkdir()
        argv = ["measurement-backup", "--source", str(self.source),
                "--runtime", str(self.root / "runtime"), "--state", str(self.root / "staging"),
                "--output", str(self.root / "output"), "--owner", backup.pwd.getpwuid(os.getuid()).pw_name,
                "--age", shutil.which("false"), "--zstd", ZSTD, "--recipient", "unused"]
        with patch("sys.argv", argv), self.assertRaises((RuntimeError, BrokenPipeError)):
            backup.main()
        self.assertEqual(list((self.root / "output").iterdir()), [])
        self.assertEqual(list((self.root / "runtime").iterdir()), [])
        self.assertEqual([p for p in (self.root / "staging").iterdir() if p.suffix == ".partial"], [])


if __name__ == "__main__":
    unittest.main()
