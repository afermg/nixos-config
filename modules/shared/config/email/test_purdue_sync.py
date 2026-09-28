"""Exercise the production Purdue channel rules using isolated Maildir stores.

Run: python3 -m unittest discover -s modules/shared/config/email -p 'test_*.py'
No credentials, IMAP servers, real mailboxes, or user sync state are accessed.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


CONFIG = Path(__file__).with_name("mbsyncrc")
MBSYNC = shutil.which("mbsync")


def channel(name):
    text = CONFIG.read_text()
    return re.search(
        rf"^Channel {re.escape(name)}\n.*?(?=^Channel |\Z)",
        text,
        re.MULTILINE | re.DOTALL,
    ).group()


@unittest.skipUnless(MBSYNC, "mbsync is required for Maildir integration tests")
class PurdueSyncTests(unittest.TestCase):
    folders = ("INBOX", "Archive", "Junk Email", "Deleted Items", "Drafts", "Sent Items")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="purdue policy test ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.far = self.root / "far"
        self.near = self.root / "near"
        for store in (self.far, self.near):
            for folder in self.folders:
                self.make_folder(store, folder)
        self.config = self.root / "mbsyncrc"
        self.config.write_text(
            f'MaildirStore purdue-remote\nSubFolders Verbatim\n'
            f'Path "{self.far}/"\nInbox "{self.far}/Inbox"\n\n'
            f'MaildirStore purdue-local\nSubFolders Verbatim\n'
            f'Path "{self.near}/"\nInbox "{self.near}/Inbox"\n\n'
            + channel("purdue") + "\n" + channel("purdue-sent")
        )

    @staticmethod
    def folder_path(store, folder):
        return store / ("Inbox" if folder == "INBOX" else folder)

    def make_folder(self, store, folder):
        path = self.folder_path(store, folder)
        for leaf in ("cur", "new", "tmp"):
            (path / leaf).mkdir(parents=True, exist_ok=True)
        return path

    def message(self, store, folder, name):
        directory = self.make_folder(store, folder)
        path = directory / "cur" / f"{name}:2,"
        path.write_bytes(
            f"Message-ID: <{name}@sync-test.invalid>\n"
            f"Date: Fri, 18 Sep 2026 10:00:00 -0400\n"
            f"Subject: {name}\n\nTest message {name}.\n".encode()
        )
        return path

    def messages(self, store, folder):
        path = self.folder_path(store, folder)
        return sorted(
            p for leaf in ("cur", "new") for p in (path / leaf).glob("*")
            if p.is_file() and not p.name.startswith(".")
        )

    def sync(self, *channels):
        result = subprocess.run(
            [MBSYNC, "-c", str(self.config), *(channels or ("-a",))],
            capture_output=True, text=True, timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_downloads_all_received_folders_but_never_uploads_local_copies(self):
        for number, folder in enumerate(self.folders[:-1]):
            self.message(self.far, folder, f"remote-{number}")
        self.message(self.far, "New Folder", "remote-new-folder")
        self.sync()
        for number, folder in enumerate(self.folders[:-1]):
            self.assertEqual(len(self.messages(self.near, folder)), 1)
            self.message(self.near, folder, f"local-copy-{number}")
        self.message(self.near, "New Folder", "local-new-folder")
        self.sync()
        self.sync()  # Unpaired local messages must stay blocked on later runs too.
        for folder in (*self.folders[:-1], "New Folder"):
            self.assertEqual(len(self.messages(self.far, folder)), 1, folder)
            self.assertEqual(len(self.messages(self.near, folder)), 2, folder)

    def test_local_flags_and_deletions_do_not_modify_purdue(self):
        for number, folder in enumerate(self.folders[:-1]):
            self.message(self.far, folder, f"remote-{number}")
        self.sync()
        for folder in self.folders[:-1]:
            path = self.messages(self.near, folder)[0]
            path.rename(path.with_name(path.name.split(":2,")[0] + ":2,SF"))
        self.sync()
        for folder in self.folders[:-1]:
            self.assertTrue(self.messages(self.far, folder)[0].name.endswith(":2,"))
            self.messages(self.near, folder)[0].unlink()
        self.sync()
        for folder in self.folders[:-1]:
            self.assertEqual(len(self.messages(self.far, folder)), 1, folder)

    def test_local_move_to_trash_does_not_delete_or_duplicate_source(self):
        self.message(self.far, "INBOX", "move-me")
        self.sync()
        path = self.messages(self.near, "INBOX")[0]
        path.rename(self.near / "Deleted Items" / "cur" / "moved-copy:2,S")
        self.sync()
        self.assertEqual(len(self.messages(self.far, "INBOX")), 1)
        self.assertEqual(len(self.messages(self.far, "Deleted Items")), 0)

    def test_local_deleted_flag_does_not_expunge_source(self):
        self.message(self.far, "INBOX", "keep-source")
        self.sync()
        path = self.messages(self.near, "INBOX")[0]
        path.rename(path.with_name(path.name.split(":2,")[0] + ":2,T"))
        self.sync()
        self.assertEqual(len(self.messages(self.far, "INBOX")), 1)

    def test_server_cleanup_and_flags_still_propagate_locally(self):
        self.message(self.far, "INBOX", "source-cleanup")
        self.sync()
        path = self.messages(self.far, "INBOX")[0]
        path.rename(path.with_name(path.name.split(":2,")[0] + ":2,S"))
        self.sync()
        self.assertTrue(self.messages(self.near, "INBOX")[0].name.endswith(":2,S"))
        self.messages(self.far, "INBOX")[0].unlink()
        self.sync()
        self.assertEqual(self.messages(self.near, "INBOX"), [])

    def test_sent_mail_uploads_and_downloads_without_duplicate_processing(self):
        self.message(self.far, "Sent Items", "sent-remote")
        self.message(self.near, "Sent Items", "sent-local")
        self.sync()
        for store in (self.far, self.near):
            self.assertEqual(len(self.messages(store, "Sent Items")), 2)
        self.sync()
        for store in (self.far, self.near):
            self.assertEqual(len(self.messages(store, "Sent Items")), 2)
        # The received-mail channel must never touch Sent, even for downloads.
        self.message(self.far, "Sent Items", "sent-later")
        self.sync("purdue")
        self.assertEqual(len(self.messages(self.near, "Sent Items")), 2)
        self.sync("purdue-sent")
        self.assertEqual(len(self.messages(self.near, "Sent Items")), 3)

    def test_arrival_timestamps_survive_downloads_and_sent_uploads(self):
        timestamp = 1700000000
        received = self.message(self.far, "INBOX", "old-received")
        sent = self.message(self.near, "Sent Items", "old-sent")
        for path in (received, sent):
            os.utime(path, (timestamp, timestamp))
        self.sync()
        for store, folder in ((self.near, "INBOX"), (self.far, "Sent Items")):
            self.assertEqual(int(self.messages(store, folder)[0].stat().st_mtime), timestamp)

    def test_split_reuses_existing_sent_state(self):
        # Establish state under the original single-channel policy, then split.
        revised = self.config.read_text()
        prefix = revised.split("Channel purdue\n", 1)[0]
        self.config.write_text(
            prefix + "Channel purdue\nFar :purdue-remote:\nNear :purdue-local:\n"
            "Patterns *\nSync All\nCreate Both\nExpunge Both\nSyncState *\n"
        )
        self.message(self.near, "Sent Items", "already-uploaded")
        self.sync()
        state = self.near / "Sent Items" / ".mbsyncstate"
        before = state.read_bytes()
        self.config.write_text(revised)
        self.sync()
        self.assertEqual(len(self.messages(self.far, "Sent Items")), 1)
        self.assertEqual(state.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
