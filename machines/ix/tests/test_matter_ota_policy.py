"""The OTA helper must follow the configured SDK and normal Nix service PATH."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


class MatterOtaPolicyTests(unittest.TestCase):
    def test_helper_uses_configured_controllers_sdk(self):
        text = (ROOT / 'machines/ix/thread.nix').read_text()
        self.assertIn('config.services.matter-server.package.dependencies', text)
        self.assertIn('chipWheels = chipCore.src;', text)
        self.assertIn('systemd.services.matter-server.path = [ otaProvider ];', text)
        self.assertNotIn('pkgs.python3Packages.home-assistant-chip', text)

    def test_helper_reuses_nixpkgs_source_patches_and_build_environment(self):
        text = (ROOT / 'machines/ix/packages/matter-ota-provider.nix').read_text()
        self.assertIn('chipWheels.overrideAttrs', text)
        self.assertIn('(old.postPatch or "")', text)
        self.assertIn('ninjaFlags = [ "chip-ota-provider-app" ];', text)
        self.assertIn('cd examples/ota-provider-app/linux', text)
        self.assertIn('chip_config_network_layer_ble=false', text)
        self.assertIn("--no-parallel --input-glob '*ota-provider*'", text)
        self.assertIn('doInstallCheck = true;', text)
        self.assertIn('chip-ota-provider-app" --help', text)
        self.assertIn('passcode discriminator secured-device-port KVS filepath', text)
        self.assertNotIn('fetchurl', text)
        self.assertNotIn('fetchFromGitHub', text)
        self.assertNotRegex(text, r'(?m)^\s*(version|hash)\s*=')
        self.assertNotRegex(text, r'/nix/store/[a-z0-9]{32}')


if __name__ == '__main__':
    unittest.main()
