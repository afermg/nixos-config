from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).with_name("mirror-purdue.py")
SPEC = importlib.util.spec_from_file_location("mirror_purdue", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Cannot load {SCRIPT}")
mirror_purdue = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = mirror_purdue
SPEC.loader.exec_module(mirror_purdue)


class MirrorPurdueTest(unittest.TestCase):
    def test_message_id_preserves_case(self) -> None:
        self.assertEqual(
            mirror_purdue.normalize_message_id(" <Case-Sensitive@Example.COM> "),
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

            with mock.patch.object(mirror_purdue, "SOURCE_ROOT", source_root):
                candidates, duplicate_count = mirror_purdue.local_candidates()

        self.assertEqual(duplicate_count, 0)
        self.assertEqual(
            set(candidates),
            {"mid:Case@Example.COM", "mid:case@Example.COM"},
        )

    def test_fallback_header_is_deterministic(self) -> None:
        raw = b"From: sender@example.com\r\nSubject: test\r\n\r\nbody\r\n"
        key = mirror_purdue.archive_key(raw, None)
        with_header = mirror_purdue.add_fallback_key(raw, key)

        self.assertEqual(key, mirror_purdue.archive_key(raw, None))
        self.assertEqual(
            with_header.count(mirror_purdue.ARCHIVE_KEY_HEADER.encode("ascii")),
            1,
        )
        self.assertTrue(with_header.endswith(b"\r\n\r\nbody\r\n"))

    def test_maildir_flags_map_to_imap_flags(self) -> None:
        self.assertEqual(
            mirror_purdue.imap_flags(Path("message:2,DFRS")),
            r"(\Seen \Flagged \Draft \Answered)",
        )
        self.assertIsNone(mirror_purdue.imap_flags(Path("message")))


if __name__ == "__main__":
    unittest.main()
