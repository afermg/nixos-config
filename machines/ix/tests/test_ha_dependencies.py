"""HA UI/discovery integrations must have their dependencies in the Nix closure."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]


class HomeAssistantDependencyTests(unittest.TestCase):
    def test_existing_and_discovered_integrations_are_packaged(self):
        text = (ROOT / "machines/ix/services.nix").read_text()
        components = re.search(r"extraComponents\s*=\s*\[(.*?)\];", text, re.S)
        self.assertIsNotNone(components)
        actual = set(re.findall(r'"([^"]+)"', components.group(1)))
        self.assertTrue({
            "met", "roborock", "google_translate", "cast", "apple_tv",
            "androidtv_remote", "ssdp", "sonos",
        }.issubset(actual))
        self.assertNotIn("pip install", text)

    def test_usb_radio_remains_owned_by_native_thread_service(self):
        text = (ROOT / "machines/ix/thread.nix").read_text()
        self.assertIn('urlQueryString = "uart-exclusive";', text)
        self.assertNotIn('"zha"', text)
        self.assertNotIn('"homeassistant_connect_zbt2"', text)


if __name__ == "__main__":
    unittest.main()
