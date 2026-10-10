"""Keep Thread/Matter setup local, single-purpose, and free of embedded keys."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]


class ThreadPolicyTests(unittest.TestCase):
    def setUp(self):
        self.text = (ROOT / "machines/ix/thread.nix").read_text()

    def test_host_imports_thread_module(self):
        self.assertIn("./thread.nix", (ROOT / "machines/ix/default.nix").read_text())

    def test_radio_has_stable_alias_and_explicit_thread_transport(self):
        self.assertIn('ATTRS{idVendor}=="303a", ATTRS{idProduct}=="831a"', self.text)
        self.assertNotIn('ATTRS{serial}', self.text)
        self.assertIn('device = "/dev/home-assistant-thread";', self.text)
        self.assertIn('baudRate = 460800;', self.text)
        self.assertIn('flowControl = true;', self.text)
        self.assertIn('urlQueryString = "uart-exclusive";', self.text)
        self.assertNotIn('urlQueryString = "uart-reset', self.text)
        self.assertIn('ENV{SYSTEMD_WANTS}+="otbr-agent.service"', self.text)
        self.assertIn('unitConfig.ConditionPathExists = "/dev/home-assistant-thread";', self.text)
        self.assertIn('backboneInterfaces = [ "end0" ];', self.text)

    def test_management_endpoints_remain_loopback(self):
        self.assertIn('rest.listenAddress = "127.0.0.1";', self.text)
        self.assertIn('listen-address = "127.0.0.1";', self.text)
        self.assertEqual(self.text.count("openFirewall = false;"), 2)
        self.assertIn("web.enable = false;", self.text)
        self.assertNotIn('"0.0.0.0"', self.text)
        self.assertNotRegex(self.text, r'allowedTCPPorts\s*=')

    def test_discovery_and_device_packets_are_interface_scoped(self):
        self.assertIn('interfaces.end0.allowedUDPPorts = [ 5353 ];', self.text)
        rule = '-i wpan0 -s fc00::/7 -p udp --sport 5540 '
        self.assertIn('ip6tables -w -A nixos-fw ' + rule, self.text)
        self.assertIn('ip6tables -w -D nixos-fw ' + rule, self.text)
        self.assertNotIn("trustedInterfaces", self.text)
        self.assertNotRegex(self.text, r'networking\.firewall\.allowed(?:TCP|UDP)Ports')

    def test_only_required_integrations_are_added(self):
        components = re.search(r'extraComponents\s*=\s*\[(.*?)\];', self.text, re.S)
        self.assertIsNotNone(components)
        self.assertEqual(re.findall(r'"([^"]+)"', components.group(1)), ["matter", "otbr", "thread"])
        self.assertIn('config.zeroconf = { };', self.text)
        self.assertNotIn('default_config', self.text)
        self.assertNotIn('hardware.bluetooth.enable', self.text)
        self.assertNotRegex(self.text, r'"zha"|"homeassistant_connect_zbt2"')

    def test_invalid_paa_is_rejected_without_disabling_attestation(self):
        self.assertIn('matter-skip-malformed-paa.patch', self.text)
        self.assertIn('tests/test_matter_paa.py', self.text)
        patch = (ROOT / 'machines/ix/patches/matter-skip-malformed-paa.patch').read_text()
        self.assertIn('+        except ValueError:', patch)
        self.assertIn('+            return False', patch)
        self.assertNotIn('ignore_ssl', self.text)
        self.assertNotIn('disable-server-interactions', self.text)

    def test_pairing_state_is_private_without_embedded_keys(self):
        self.assertEqual(self.text.count('StateDirectoryMode = "0700";'), 2)
        self.assertNotRegex(self.text, r'(?i)(networkkey|pskc|dataset|pairing.code)\s*=')


if __name__ == "__main__":
    unittest.main()
