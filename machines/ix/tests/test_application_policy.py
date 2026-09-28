"""Regression checks for deliberate migration-stage safety boundaries."""
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]
HOME = ROOT / "homes/ix"


class ApplicationPolicyTests(unittest.TestCase):
    def test_ix_identity_and_dns_transport(self):
        host = (ROOT / "machines/ix/default.nix").read_text()
        self.assertIn('networking.hostName = "ix";', host)
        self.assertIn('shell = pkgs.fish;', host)
        sync = (HOME / "syncthing.nix").read_text()
        self.assertNotRegex(sync, r'tcp://(?:100|192|10|172)\.')
        self.assertIn('moby.tail5e510f.ts.net', sync)

    def test_device_id_is_not_in_documentation(self):
        for path in (ROOT / "machines/ix").glob("*.md"):
            self.assertNotRegex(path.read_text(), r'\b[A-Z2-7]{7}(?:-[A-Z2-7]{7}){7}\b')

    def test_mail_policies_preserve_source_account_directions(self):
        expected = {
            "quasimorphic": ("All", "Both"),
            "quasimorphic-archives": ("All", "Both"),
            "broad": ("All", "Both"),
            "broad-all-mail": ("Pull", "None"),
            "purdue": ("Pull", "Near"),
            "purdue-sent": ("All", "Both"),
        }
        channels = re.split(r"(?m)^Channel ", (HOME / "mbsyncrc").read_text())[1:]
        self.assertEqual(len(channels), len(expected))
        for channel in channels:
            sync, expunge = expected[channel.splitlines()[0]]
            self.assertEqual(re.findall(r"(?m)^Sync (.+)$", channel), [sync])
            self.assertEqual(re.findall(r"(?m)^Expunge (.+)$", channel), [expunge])
            self.assertEqual(re.findall(r"(?m)^Remove (.+)$", channel), ["None"])
            self.assertIn("SyncState *", channel)

    def test_credentials_are_commands_not_embedded_passwords(self):
        text = (HOME / "mbsyncrc").read_text()
        self.assertNotRegex(text, r"(?m)^Pass\s")
        self.assertEqual(len(re.findall(r"(?m)^PassCmd ", text)), 3)
        mail = (HOME / "mail.nix").read_text()
        self.assertIn("mail-seed-complete", mail)
        self.assertIn("flock -n 9", mail)
        self.assertIn("MIRROR_MAIL_PASSWORD_FILE", mail)

    def test_shared_editor_and_local_mail_credentials(self):
        text = (HOME / "emacs.el").read_text()
        self.assertIn("modules/shared/config/emacs/init.el", text)
        self.assertIn("mu4e-update-interval 300", text)
        self.assertIn("mail-index-complete", text)
        self.assertIn("afm/mu4e-install-safe-delete", text)
        self.assertIn("ix-mail-credentials-locked-p", text)
        shared = (ROOT / "modules/shared/config/emacs/config.org").read_text()
        self.assertNotIn("org-gcal", shared)

    def test_agent_has_no_moby_extension_dependency(self):
        settings = json.loads((HOME / "pi-settings.json").read_text())
        self.assertEqual(settings["packages"], [])
        self.assertEqual(settings["extensions"], [])
        self.assertEqual(settings["defaultProjectTrust"], "ask")
        self.assertFalse(settings["enableInstallTelemetry"])
        self.assertFalse(settings["enableAnalytics"])

    def test_sync_stays_private_paused_and_session_scoped(self):
        text = (HOME / "syncthing.nix").read_text()
        for name in ("globalAnnounceEnabled", "localAnnounceEnabled", "relaysEnabled"):
            self.assertIn(f"{name} = false;", text)
        self.assertEqual(text.count("paused = true;"), 2)
        self.assertIn('guiAddress = "127.0.0.1:8384";', text)
        self.assertIn('/.pi/agent/sessions"', text)
        self.assertNotIn('/.pi/agent"', text)

    def test_home_assistant_is_minimal_and_fresh(self):
        text = (ROOT / "machines/ix/services.nix").read_text()
        self.assertIn('server_host = "127.0.0.1";', text)
        self.assertNotIn('"roborock"', text)
        self.assertNotIn("ConditionPathExists", text)
        self.assertNotIn("raspi4-ha-check", text)
        self.assertIn("firewall.interfaces.tailscale0.allowedTCPPorts", text)


if __name__ == "__main__":
    unittest.main()
