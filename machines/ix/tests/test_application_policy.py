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
        self.assertIn('shell = pkgs.bashInteractive;', host)
        self.assertIn('programs.fish.enable = false;', host)
        sync = (HOME / "syncthing.nix").read_text()
        self.assertNotRegex(sync, r'tcp://(?:100|192|10|172)\.')
        self.assertIn('moby.tail5e510f.ts.net', sync)

    def test_ix_shell_has_no_fish_plugins_or_atuin_sync(self):
        home = (HOME / 'home.nix').read_text()
        apps = (HOME / 'applications.nix').read_text()
        tools = (HOME / 'editor-tools.nix').read_text()
        self.assertIn('programs.bash.enable = true;', home)
        self.assertIn('programs.fish.enable = false;', home)
        self.assertIn('programs.atuin.enable = false;', home)
        self.assertNotIn('config/atuin/atuin.nix', home)
        self.assertNotIn('config/fish/fish.nix', apps)
        self.assertNotRegex(tools, r'(?m)^\s*fish\s*$')

    def test_ghostel_can_use_bash_without_fish(self):
        shared = (ROOT / 'modules/shared/config/emacs/config.org').read_text()
        self.assertRegex(shared, r'\(or \(executable-find "fish"\)\s*\(executable-find "bash"\)')
        self.assertNotIn('Ghostel requires fish, but fish is not on Emacs exec-path', shared)

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
        self.assertIn('unitConfig.ConditionPathExists = "/home/amunoz/.local/state/hindsight-codex/auth.json";', service)
        self.assertIn('CODEX_HOME = "/home/hindsight/.codex";', service)
        self.assertIn('HINDSIGHT_API_LLM_PROVIDER = "none";', service)
        self.assertIn('HINDSIGHT_API_WORKER_ENABLED = "false";', service)
        self.assertIn('HINDSIGHT_API_EMBEDDINGS_PROVIDER = "openai-codex";', service)
        self.assertIn('HINDSIGHT_API_RERANKER_PROVIDER = "rrf";', service)
        self.assertIn('networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 8888 ];', service)
        self.assertIn('api_url = "http://ix.tail5e510f.ts.net:8888";', shared_client)
        self.assertIn('const DEFAULT_API_URL = "http://ix.tail5e510f.ts.net:8888";', extension)
        self.assertNotIn("100.94.5.85", home + shared_client + extension)
        self.assertNotRegex(service, r"hsk_[A-Za-z0-9]")
        apps = (HOME / "applications.nix").read_text()
        self.assertIn("codex", apps)

    def test_pi_msg_relay_moves_to_ix_without_embedded_password(self):
        home = (HOME / "home.nix").read_text()
        relay = (ROOT / "machines/ix/ejabberd.nix").read_text()
        secrets = (ROOT / "secrets/secrets.nix").read_text()
        module = (ROOT / "modules/shared/config/pi-msg/pi-msg.nix").read_text()
        flake = (ROOT / "flake.nix").read_text()
        moby = (ROOT / "machines/moby/default.nix").read_text()
        self.assertIn("../../modules/shared/config/pi-msg/pi-msg.nix", home)
        self.assertIn('age.identityPaths = [ "/home/amunoz/.ssh/id_ed25519_github_ix" ];', home)
        self.assertIn('domain = "ix.tail5e510f.ts.net";', home + relay)
        self.assertIn('secretFile = ../../secrets/pi-msg-ix.age;', home)
        self.assertIn('botUsername = "ix";', home)
        self.assertIn("registerLocalAccounts = true;", home)
        self.assertIn("requireAccountsReadyMarker = true;", home)
        self.assertIn('tailscaleIPv4 = "100.114.49.10";', relay)
        self.assertIn("networking.firewall.interfaces.tailscale0.allowedTCPPorts", relay)
        self.assertIn('"pi-msg-ix.age".publicKeys', secrets)
        self.assertIn('"pi-msg-moby-ix.age".publicKeys', secrets)
        self.assertIn('"pi-msg-oppy-ix.age".publicKeys', secrets)
        self.assertIn('domain = "ix.tail5e510f.ts.net";', flake)
        self.assertIn('secretFile = ./secrets/pi-msg-moby-ix.age;', flake)
        self.assertIn('secretFile = ./secrets/pi-msg-oppy-ix.age;', flake)
        self.assertIn('registrationSshHost = "ix.tail5e510f.ts.net";', flake)
        self.assertIn('secretFile = ../../secrets/pi-msg-moby-ix.age;', moby)
        self.assertNotRegex(moby, r'(?m)^\s*\./ejabberd\.nix\s*$')
        self.assertIn("registered_users", module)
        self.assertNotIn("check_account", module)
        self.assertNotRegex(home + relay + secrets, r"hsk_[A-Za-z0-9]")

    def test_sync_stays_private_paused_and_session_scoped(self):
        text = (HOME / "syncthing.nix").read_text()
        for name in ("globalAnnounceEnabled", "localAnnounceEnabled", "relaysEnabled"):
            self.assertIn(f"{name} = false;", text)
        self.assertEqual(text.count("paused = true;"), 3)
        self.assertIn('guiAddress = "127.0.0.1:8384";', text)
        self.assertIn('/.pi/agent/sessions"', text)
        self.assertIn('id = "ix-backups";', text)
        self.assertIn('type = "sendonly";', text)
        self.assertNotIn('/.pi/agent"', text)

    def test_ix_state_backups_are_encrypted_and_not_live_database_sync(self):
        text = (ROOT / "machines/ix/backups.nix").read_text()
        self.assertIn("ix-state-backup.service", text)
        self.assertIn("systemd.timers.ix-state-backup", text)
        self.assertIn(".local/share/syncthing/ix-backups/ix", text)
        self.assertIn("age -d -i /etc/ssh/ssh_host_ed25519_key", text)
        self.assertIn("home/amunoz/.pi/agent/sessions", text)
        self.assertIn("home/amunoz/.elfeed", text)
        self.assertIn("home/amunoz/.local/state/syncthing/key.pem", text)
        self.assertIn("var/lib/blocky", text)
        self.assertIn("var/lib/private/blocky", text)
        self.assertNotIn("/var/lib/hindsight/pg0", text)

    def test_dns_blocking_has_explicit_listeners_and_not_client_cutover(self):
        text = (ROOT / "machines/ix/dns.nix").read_text()
        self.assertIn("services.blocky", text)
        self.assertIn('lanAddress = "192.168.1.162";', text)
        self.assertRegex(text, r'dns = \[\s*"100\.114\.49\.10:53"\s*"\$\{lanAddress\}:53"\s*\];')
        self.assertIn("https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/multi.txt", text)
        self.assertIn('http = "127.0.0.1:4000";', text)
        self.assertIn("https://dns.quad9.net/dns-query", text)
        self.assertIn("https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts", text)
        self.assertIn("tail5e510f.ts.net", text)
        self.assertIn("allowedTCPPorts = [ 53 ];", text)
        self.assertIn("allowedUDPPorts = [ 53 ];", text)
        self.assertNotIn("0.0.0.0:53", text)
        host = (ROOT / "machines/ix/default.nix").read_text()
        self.assertIn("./dns.nix", host)

    def test_dns_lan_firewall_is_ipv4_interface_and_subnet_scoped(self):
        text = (ROOT / "machines/ix/dns.nix").read_text()
        self.assertIn(
            '-i end0 -s 192.168.1.0/24 -d ${lanAddress}/32 -p ${protocol} --dport 53 '
            '-m comment --comment ix-blocky-lan-${protocol} -j nixos-fw-accept',
            text,
        )
        for protocol in ("tcp", "udp"):
            self.assertIn('iptables -w -A nixos-fw ${lanDnsRule "' + protocol + '"}', text)
            self.assertIn('iptables -w -D nixos-fw ${lanDnsRule "' + protocol + '"} 2>/dev/null || true', text)
        self.assertNotRegex(text, r'networking\.firewall\.allowed(?:TCP|UDP)Ports')
        self.assertNotRegex(text, r'trustedInterfaces\s*=\s*\[[^]]*"end0"')
        self.assertNotIn('[::]', text)
        self.assertNotIn('networking.nameservers', text)
        self.assertNotIn('services.tailscale', text)

    def test_dns_private_policy_uses_root_only_runtime_credentials(self):
        text = (ROOT / "machines/ix/dns.nix").read_text()
        self.assertIn('age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];', text)
        self.assertRegex(
            text,
            r'age\.secrets\.blocky-private = \{\s*'
            r'file = ../../secrets/blocky-private\.yaml\.age;\s*'
            r'mode = "0400";\s*owner = "root";\s*group = "root";',
        )
        self.assertIn('"00-public.yaml:${publicConfig}"', text)
        self.assertIn('"10-private.yaml:${config.age.secrets.blocky-private.path}"', text)
        self.assertIn('enableConfigCheck = true;', text)
        self.assertIn('restartTriggers = [ config.age.secrets.blocky-private.file ];', text)
        self.assertIn('ExecStartPre = [ "${lib.getExe config.services.blocky.package} --config %d validate" ];', text)
        self.assertIn('ExecStart = lib.mkForce "${lib.getExe config.services.blocky.package} --config %d";', text)
        self.assertNotIn('builtins.readFile', text)
        recipients = (ROOT / "secrets/secrets.nix").read_text()
        self.assertRegex(
            recipients,
            r'"blocky-private\.yaml\.age"\.publicKeys = \[\s*personal_key\s*ix_host_key\s*\];',
        )
        encrypted = (ROOT / "secrets/blocky-private.yaml.age").read_bytes()
        self.assertTrue(encrypted.startswith(b"age-encryption.org/v1\n"))
        ignored = (ROOT / ".gitignore").read_text().splitlines()
        for name in ("yaml", "yml", "json", "yaml.decrypted"):
            self.assertIn("/secrets/blocky-private." + name, ignored)

    def test_home_assistant_is_minimal_with_explicit_roborock_dependencies(self):
        text = (ROOT / "machines/ix/services.nix").read_text()
        self.assertIn('server_host = "127.0.0.1";', text)
        components = re.search(r"extraComponents\s*=\s*\[([^]]*)\]", text)
        self.assertIsNotNone(components)
        self.assertEqual(re.findall(r'"([^"]+)"', components.group(1)), [
            "met", "roborock", "google_translate", "cast", "apple_tv",
            "androidtv_remote", "ssdp", "sonos",
        ])
        self.assertNotRegex(text, r"(?m)^\s*default_config\s*=")
        self.assertNotRegex(text, r"(?m)^\s*roborock\s*=")
        self.assertNotIn("ConditionPathExists", text)
        self.assertNotIn("raspi4-ha-check", text)
        self.assertIn("firewall.interfaces.tailscale0.allowedTCPPorts", text)

    def test_home_assistant_pins_matter_time_sync(self):
        text = (ROOT / "machines/ix/services.nix").read_text()
        self.assertIn("pkgs.buildHomeAssistantComponent", text)
        self.assertIn('domain = "matter_time_sync";', text)
        self.assertIn('version = "2.2.2";', text)
        self.assertIn('rev = "e74b7d7c339c476a87eb2778c613f93a22f9f54b";', text)
        self.assertIn('hash = "sha256-e5XxmIE/QWDJK9cVZZ3aFksXzLf+PxPIAbODhcy7RAw=";', text)
        self.assertIn("pkgs.home-assistant.python3Packages.aiohttp", text)
        self.assertNotRegex(text, r'allowedTCPPorts\s*=\s*\[[^]]*\b5580\b')

    def test_home_assistant_records_electrical_measurements(self):
        text = (ROOT / "machines/ix/services.nix").read_text()
        self.assertIn("energy = { };", text)
        self.assertIn("history = { };", text)
        recorder = re.search(r'recorder\s*=\s*\{\s*include.entities\s*=\s*\[([^]]*)\]', text)
        self.assertIsNotNone(recorder)
        self.assertEqual(re.findall(r'"([^"]+)"', recorder.group(1)), [
            "sensor.kitchen_grillplats_plug_fridge_energy",
            "sensor.kitchen_grillplats_plug_fridge_power",
        ])
        self.assertNotIn('"sensor.*power*"', text)
        self.assertNotRegex(text, r"(?m)^\s*default_config\s*=")

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
