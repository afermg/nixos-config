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

    def test_hindsight_moves_to_ix_without_embedded_token(self):
        home = (HOME / "hindsight.nix").read_text()
        service = (ROOT / "machines/ix/hindsight.nix").read_text()
        shared_client = (ROOT / "modules/shared/config/hindsight/client.nix").read_text()
        extension = (ROOT / "modules/shared/config/hindsight/hindsight.ts").read_text()
        self.assertIn('api_url = "http://127.0.0.1:8888";', home)
        self.assertIn('token_file = "${home}/.config/hindsight/api-token";', home)
        self.assertIn('".pi/agent/extensions/hindsight.ts"', home)
        self.assertIn('ports = [ "0.0.0.0:8888:8888" ];', service)
        self.assertIn('HINDSIGHT_API_LLM_PROVIDER = "none";', service)
        self.assertIn('HINDSIGHT_API_WORKER_ENABLED = "false";', service)
        self.assertIn('networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 8888 ];', service)
        self.assertIn('api_url = "http://ix.tail5e510f.ts.net:8888";', shared_client)
        self.assertIn('const DEFAULT_API_URL = "http://ix.tail5e510f.ts.net:8888";', extension)
        self.assertNotIn("100.94.5.85", home + shared_client + extension)
        self.assertNotRegex(service, r"hsk_[A-Za-z0-9]")

    def test_sync_stays_private_paused_and_session_scoped(self):
        text = (HOME / "syncthing.nix").read_text()
        for name in ("globalAnnounceEnabled", "localAnnounceEnabled", "relaysEnabled"):
            self.assertIn(f"{name} = false;", text)
        self.assertEqual(text.count("paused = true;"), 2)
        self.assertIn('guiAddress = "127.0.0.1:8384";', text)
        self.assertIn('/.pi/agent/sessions"', text)
        self.assertNotIn('/.pi/agent"', text)

    def test_home_assistant_is_minimal_with_explicit_roborock_dependencies(self):
        text = (ROOT / "machines/ix/services.nix").read_text()
        self.assertIn('server_host = "127.0.0.1";', text)
        components = re.search(r"extraComponents\s*=\s*\[([^]]*)\]", text)
        self.assertIsNotNone(components)
        self.assertEqual(re.findall(r'"([^"]+)"', components.group(1)), ["met", "roborock"])
        self.assertNotRegex(text, r"(?m)^\s*default_config\s*=")
        self.assertNotRegex(text, r"(?m)^\s*roborock\s*=")
        self.assertNotIn("ConditionPathExists", text)
        self.assertNotIn("raspi4-ha-check", text)
        self.assertIn("firewall.interfaces.tailscale0.allowedTCPPorts", text)

    def test_home_assistant_explicitly_enables_companion_app(self):
        text = (ROOT / "machines/ix/services.nix").read_text()
        config = text.split('    config = {', 1)[1]
        self.assertIn('mobile_app = { };', config)
        self.assertNotRegex(config, r'(?m)^\s*default_config\s*=')
        self.assertIn('server_host = "127.0.0.1";', config)

    def test_home_assistant_lan_proxy_preserves_private_backend(self):
        text = (ROOT / "machines/ix/services.nix").read_text()
        self.assertIn('systemd.sockets.home-assistant-lan = {', text)
        self.assertIn('wantedBy = [ "sockets.target" ];', text)
        self.assertIn('listenStreams = [ "0.0.0.0:8124" ];', text)
        self.assertIn('socketConfig.BindToDevice = "end0";', text)
        self.assertIn('requires = [ "home-assistant.service" ];', text)
        self.assertIn('systemd-socket-proxyd 127.0.0.1:8123";', text)
        self.assertIn('DynamicUser = true;', text)
        self.assertIn('ProtectSystem = "strict";', text)
        self.assertRegex(text, r'RestrictAddressFamilies = \[\s*"AF_INET"\s*"AF_UNIX"\s*\];')
        self.assertIn('server_host = "127.0.0.1";', text)
        self.assertNotRegex(text, r"(?m)^\s*(trusted_networks|trusted_proxies|use_x_forwarded_for)\s*=")
        self.assertNotIn('[::]', text)

    def test_home_assistant_lan_firewall_is_ipv4_subnet_scoped(self):
        text = (ROOT / "machines/ix/services.nix").read_text()
        rule = re.search(r'homeAssistantLanRule = "([^"]+)";', text)
        self.assertIsNotNone(rule)
        self.assertEqual(
            rule.group(1),
            '-i end0 -s 192.168.1.0/24 -d 192.168.1.0/24 -p tcp --dport 8124 '
            '-m comment --comment ix-home-assistant-lan -j nixos-fw-accept',
        )
        self.assertIn('iptables -w -A nixos-fw ${homeAssistantLanRule}', text)
        self.assertIn('iptables -w -D nixos-fw ${homeAssistantLanRule} 2>/dev/null || true', text)
        self.assertNotRegex(text, r'allowedTCPPorts\s*=\s*\[[^]]*\b812[34]\b')
        self.assertNotRegex(text, r'trustedInterfaces\s*=\s*\[[^]]*"end0"')


if __name__ == "__main__":
    unittest.main()
