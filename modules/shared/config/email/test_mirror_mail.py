from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).with_name("mirror-mail.py")
SPEC = importlib.util.spec_from_file_location("mirror_mail", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Cannot load {SCRIPT}")
mirror_mail = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = mirror_mail
SPEC.loader.exec_module(mirror_mail)


class FakeConnection:
    def __init__(self) -> None:
        self.appended: list[tuple[str, str | None, str, bytes]] = []

    def select(self, _folder: str, readonly: bool = False) -> tuple[str, list[bytes]]:
        return "OK", [b""]

    def append(
        self, folder: str, flags: str | None, date: str, raw: bytes
    ) -> tuple[str, list[bytes]]:
        self.appended.append((folder, flags, date, raw))
        return "OK", [b""]


class MirrorMailTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.history = self.enterContext(
            mirror_mail.ImportHistory(self.root / "imports.sqlite3")
        )
        for config in mirror_mail.MIRRORS.values():
            self.history.remember(config, set(), initialize=True)

    def test_message_id_preserves_case(self) -> None:
        self.assertEqual(
            mirror_mail.normalize_message_id(" <Case-Sensitive@Example.COM> "),
            "mid:Case-Sensitive@Example.COM",
        )

    def test_case_distinct_message_ids_are_not_deduplicated(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            source_root = Path(temporary_directory)
            maildir = source_root / "Inbox" / "cur"
            maildir.mkdir(parents=True)
            (maildir / "first:2,S").write_bytes(
                b"Message-ID: <Case@Example.COM>\r\n\r\nfirst\r\n"
            )
            (maildir / "second:2,S").write_bytes(
                b"Message-ID: <case@Example.COM>\r\n\r\nsecond\r\n"
            )

            candidates, duplicate_count = mirror_mail.local_candidates((source_root,))

        self.assertEqual(duplicate_count, 0)
        self.assertEqual(
            set(candidates),
            {"mid:Case@Example.COM", "mid:case@Example.COM"},
        )

    def test_duplicate_across_label_and_all_mail_roots_is_archived_once(self) -> None:
        raw = b"Message-ID: <same@example.com>\r\n\r\nbody\r\n"
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            label_root = root / "labels"
            all_mail_root = root / "all-mail"
            for source_root in (label_root, all_mail_root):
                maildir = source_root / "Inbox" / "cur"
                maildir.mkdir(parents=True)
                (maildir / "message:2,S").write_bytes(raw)

            candidates, duplicate_count = mirror_mail.local_candidates(
                (label_root, all_mail_root)
            )

        self.assertEqual(len(candidates), 1)
        self.assertEqual(duplicate_count, 1)

    def test_fallback_header_is_deterministic(self) -> None:
        raw = b"From: sender@example.com\r\nSubject: test\r\n\r\nbody\r\n"
        key = mirror_mail.archive_key(raw, None)
        with_header = mirror_mail.add_fallback_key(raw, key)

        self.assertEqual(key, mirror_mail.archive_key(raw, None))
        self.assertEqual(
            with_header.count(mirror_mail.ARCHIVE_KEY_HEADER.encode("ascii")),
            1,
        )
        self.assertTrue(with_header.endswith(b"\r\n\r\nbody\r\n"))

    def test_maildir_flags_map_to_imap_flags(self) -> None:
        self.assertEqual(
            mirror_mail.imap_flags(Path("message:2,DFRS")),
            r"(\Seen \Flagged \Draft \Answered)",
        )
        self.assertIsNone(mirror_mail.imap_flags(Path("message")))

    def test_broad_spam_targets_mxroute_junk(self) -> None:
        config = mirror_mail.MIRRORS["broad-spam"]

        self.assertEqual(config.destination_folder, "Junk")
        self.assertEqual(config.source_roots[0].parts[-2:], ("[Gmail]", "Spam"))

    def test_broad_archive_appends_complete_searchable_message(self) -> None:
        raw = (
            b"From: sender@example.com\r\n"
            b"Subject: Searchable title\r\n"
            b"Message-ID: <searchable@example.com>\r\n"
            b"Date: Tue, 15 Sep 2026 12:00:00 -0400\r\n"
            b"Content-Type: text/plain; charset=utf-8\r\n"
            b"\r\n"
            b"Searchable message body\r\n"
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            source_root = Path(temporary_directory)
            maildir = source_root / "Inbox" / "cur"
            maildir.mkdir(parents=True)
            (maildir / "message:2,S").write_bytes(raw)
            config = mirror_mail.MirrorConfig(
                name="broad",
                label="Broad",
                source_roots=(source_root,),
                destination_folder="INBOX.Broad-Archive",
            )
            connection = FakeConnection()

            with mock.patch.object(mirror_mail, "remote_keys", return_value=set()):
                result = mirror_mail.mirror_account(
                    connection, config, max_new_messages=500, history=self.history
                )

        self.assertEqual(result.appended, 1)
        self.assertEqual(result.deferred, 0)
        self.assertEqual(result.errors, ())
        self.assertEqual(len(connection.appended), 1)
        folder, _flags, _date, appended_raw = connection.appended[0]
        self.assertEqual(folder, '"INBOX.Broad-Archive"')
        self.assertEqual(appended_raw, raw)
        self.assertIn(b"Subject: Searchable title", appended_raw)
        self.assertIn(b"Searchable message body", appended_raw)

    def test_empty_message_id_gets_fallback_key_for_idempotency(self) -> None:
        raw = b"Subject: empty id\r\nMessage-ID: < >\r\n\r\nbody\r\n"
        with tempfile.TemporaryDirectory() as temporary_directory:
            source_root = Path(temporary_directory)
            maildir = source_root / "Inbox" / "cur"
            maildir.mkdir(parents=True)
            (maildir / "message:2,S").write_bytes(raw)
            config = mirror_mail.MirrorConfig(
                name="broad",
                label="Broad",
                source_roots=(source_root,),
                destination_folder="INBOX.Broad-Archive",
            )
            connection = FakeConnection()

            with mock.patch.object(mirror_mail, "remote_keys", return_value=set()):
                first_result = mirror_mail.mirror_account(
                    connection, config, max_new_messages=500, history=self.history
                )

            fallback_key = mirror_mail.archive_key(raw, None)
            with mock.patch.object(
                mirror_mail, "remote_keys", return_value={fallback_key}
            ):
                second_result = mirror_mail.mirror_account(
                    FakeConnection(), config, max_new_messages=500, history=self.history
                )

        self.assertEqual(first_result.appended, 1)
        appended_raw = connection.appended[0][3]
        self.assertIn(b"X-Quasimorphic-Archive-Key: sha256:", appended_raw)
        self.assertEqual(second_result.already_archived, 1)
        self.assertEqual(second_result.appended, 0)

    def test_per_run_limit_defers_remaining_messages(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            source_root = Path(temporary_directory)
            maildir = source_root / "Inbox" / "cur"
            maildir.mkdir(parents=True)
            for index in range(3):
                (maildir / f"message-{index}:2,S").write_bytes(
                    f"Message-ID: <{index}@example.com>\r\n\r\nbody\r\n".encode()
                )
            config = mirror_mail.MirrorConfig(
                name="broad",
                label="Broad",
                source_roots=(source_root,),
                destination_folder="INBOX.Broad-Archive",
            )
            connection = FakeConnection()

            with mock.patch.object(mirror_mail, "remote_keys", return_value=set()):
                result = mirror_mail.mirror_account(
                    connection, config, max_new_messages=2, history=self.history
                )

        self.assertEqual(result.appended, 2)
        self.assertEqual(result.deferred, 1)
        self.assertEqual(len(connection.appended), 2)

    def candidate_config(self):
        maildir = self.root / "source" / "Inbox" / "cur"
        maildir.mkdir(parents=True)
        (maildir / "message:2,S").write_bytes(
            b"Message-ID: <receipt@example.com>\r\n\r\nbody\r\n"
        )
        return mirror_mail.MirrorConfig(
            "broad", "Broad", (self.root / "source",), "INBOX.Broad-Archive"
        )

    def test_deleted_or_moved_import_is_not_resurrected(self):
        config = self.candidate_config()
        with mock.patch.object(mirror_mail, "remote_keys", return_value=set()):
            first = mirror_mail.mirror_account(
                FakeConnection(), config, 500, self.history
            )
            second_connection = FakeConnection()
            second = mirror_mail.mirror_account(
                second_connection, config, 500, self.history
            )
        self.assertEqual(first.appended, 1)
        self.assertEqual(second.appended, 0)
        self.assertEqual(second.previously_imported, 1)
        self.assertEqual(second_connection.appended, [])

    def test_existing_remote_copy_is_remembered_before_later_deletion(self):
        config = self.candidate_config()
        with mock.patch.object(
            mirror_mail, "remote_keys", return_value={"mid:receipt@example.com"}
        ):
            first = mirror_mail.mirror_account(
                FakeConnection(), config, 500, self.history
            )
        with mock.patch.object(mirror_mail, "remote_keys", return_value=set()):
            second = mirror_mail.mirror_account(
                FakeConnection(), config, 500, self.history
            )
        self.assertEqual(first.already_archived, 1)
        self.assertEqual(second.previously_imported, 1)
        self.assertEqual(second.appended, 0)

    def test_failed_append_is_not_recorded_and_can_be_retried(self):
        config = self.candidate_config()
        failed = FakeConnection()
        failed.append = mock.Mock(return_value=("NO", [b"failure"]))
        with mock.patch.object(mirror_mail, "remote_keys", return_value=set()):
            first = mirror_mail.mirror_account(failed, config, 500, self.history)
            second = mirror_mail.mirror_account(
                FakeConnection(), config, 500, self.history
            )
        self.assertEqual(first.appended, 0)
        self.assertEqual(len(first.errors), 1)
        self.assertEqual(second.appended, 1)

    def test_missing_receipts_fail_closed(self):
        config = self.candidate_config()
        with mirror_mail.ImportHistory(self.root / "empty.sqlite3") as empty:
            with self.assertRaisesRegex(RuntimeError, "uninitialized"):
                mirror_mail.mirror_account(FakeConnection(), config, 500, empty)

    def test_receipts_persist_and_are_per_destination(self):
        config = mirror_mail.MIRRORS["broad"]
        path = self.root / "durable.sqlite3"
        with mirror_mail.ImportHistory(path) as history:
            history.remember(config, {"mid:persist@example.com"}, initialize=True)
            history.remember(mirror_mail.MIRRORS["broad-spam"], set(), initialize=True)
        with mirror_mail.ImportHistory(path) as history:
            self.assertEqual(history.keys(config), {"mid:persist@example.com"})
            self.assertEqual(history.keys(mirror_mail.MIRRORS["broad-spam"]), set())
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_importers_cannot_overlap(self):
        with self.assertRaises(BlockingIOError):
            with mirror_mail.ImportHistory(self.history.path):
                self.fail("Second importer acquired the lock")

    def test_seed_includes_pending_deletions_and_fallback_receipts(self):
        config = mirror_mail.MIRRORS["broad"]
        local = self.root / "quasimorphic"
        folder = local / "Inbox/Broad-Archive/cur"
        folder.mkdir(parents=True)
        (folder / "deleted:2,ST").write_bytes(
            b"Message-ID: <deleted@example.com>\r\n\r\nbody"
        )
        (folder / "fallback:2,T").write_bytes(
            b"X-Quasimorphic-Archive-Key: sha256:original\r\n\r\nbody"
        )
        trash = local / "Trash/cur"
        trash.mkdir(parents=True)
        (trash / "moved:2,S").write_bytes(
            b"Message-ID: <moved@example.com>\r\n\r\nbody"
        )
        with (
            mock.patch.object(mirror_mail, "MXROUTE_MAILDIR", local),
            mock.patch.object(
                mirror_mail, "remote_keys", return_value={"mid:remote@example.com"}
            ),
        ):
            mirror_mail.record_existing(FakeConnection(), config, self.history)
        self.assertEqual(
            self.history.keys(config),
            {
                "mid:deleted@example.com",
                "sha256:original",
                "mid:moved@example.com",
                "mid:remote@example.com",
            },
        )

    def test_mxroute_channels_both_propagate_deletions(self):
        text = SCRIPT.with_name("mbsyncrc").read_text()
        for channel in ("quasimorphic", "quasimorphic-archives"):
            block = text.split(f"Channel {channel}\n", 1)[1].split("\n\n", 1)[0]
            self.assertIn("Sync All", block)
            self.assertIn("Create Both", block)
            self.assertIn("Expunge Both", block)
            self.assertNotIn("Sync Pull", block)


if __name__ == "__main__":
    unittest.main()
