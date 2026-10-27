#!/usr/bin/env python3
"""Evaluate ix SSH and destination authorization without contacting any host.

Run from any directory: python3 homes/ix/test_ssh.py
Uses path: flakes so new, deliberately unstaged source files are included.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
KEY = (ROOT / "homes/ix/id_ed25519_ix_hosts.pub").read_text().strip()


def evaluate(attribute, raw=False):
    result = subprocess.check_output(
        ["nix", "eval", "--raw" if raw else "--json", f"path:{ROOT}#{attribute}"],
        text=True,
        timeout=120,
    )
    return result if raw else json.loads(result)


class IxSshTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.config = Path(cls.temp.name) / "config"
        cls.config.write_text(evaluate(
            'nixosConfigurations.ix.config.home-manager.users.amunoz.home.file.".ssh/config".text',
            raw=True,
        ))

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def effective(self, host):
        # -G only expands configuration: in particular, moby is NEVER probed.
        output = subprocess.check_output(
            ["ssh", "-G", "-F", str(self.config), host], text=True,
            stderr=subprocess.DEVNULL, timeout=10,
        )
        settings = {}
        for line in output.splitlines():
            key, value = line.split(" ", 1)
            settings.setdefault(key, []).append(value)
        return settings

    def test_explicit_destinations_without_agent_or_extra_identities(self):
        for aliases, hostname, user in [
            (["mbp", "alan-purdue-mbp", "alan-purdue-mbp.tail5e510f.ts.net"],
             "alan-purdue-mbp.tail5e510f.ts.net", "alan"),
            (["oppy", "oppy.tail5e510f.ts.net"], "oppy.tail5e510f.ts.net", "amunoz"),
            (["moby", "moby.tail5e510f.ts.net"], "moby.tail5e510f.ts.net", "amunoz"),
        ]:
            for alias in aliases:
                with self.subTest(alias=alias):
                    settings = self.effective(alias)
                    for key, value in {
                        "hostname": hostname, "user": user,
                        "identityfile": "/home/amunoz/.ssh/id_ed25519_ix_hosts",
                        "identityagent": "none", "identitiesonly": "yes",
                        "forwardagent": "no", "stricthostkeychecking": "true",
                        "userknownhostsfile": "/home/amunoz/.ssh/known_hosts_ix",
                    }.items():
                        self.assertEqual(settings[key], [value])

    def test_unrelated_hosts_do_not_receive_dedicated_identity(self):
        settings = self.effective("example.org")
        self.assertEqual(settings["forwardagent"], ["no"])
        self.assertNotIn("/home/amunoz/.ssh/id_ed25519_ix_hosts", settings["identityfile"])
        github = self.effective("github.com")
        self.assertEqual(github["identityfile"], ["/home/amunoz/.ssh/id_ed25519_github_ix"])
        self.assertEqual(github["user"], ["git"])

    def test_pinned_host_keys_are_nix_managed(self):
        source = evaluate(
            'nixosConfigurations.ix.config.home-manager.users.amunoz.home.file.".ssh/known_hosts_ix".source'
        )
        contents = Path(source).read_text()
        self.assertEqual(contents, (ROOT / "homes/ix/ssh_known_hosts").read_text())
        self.assertEqual({line.split()[0] for line in contents.splitlines()}, {
            "alan-purdue-mbp.tail5e510f.ts.net", "oppy.tail5e510f.ts.net", "moby.tail5e510f.ts.net",
        })

    def test_oppy_home_profile_authorizes_ix(self):
        source = evaluate('homeConfigurations."amunoz@oppy".config.home.file.".ssh/authorized_keys".source')
        self.assertEqual(Path(source).read_text().strip(), KEY)

    def test_moby_declaration_authorizes_ix_without_network(self):
        files = evaluate('nixosConfigurations.moby.config.users.users.amunoz.openssh.authorizedKeys.keyFiles')
        self.assertIn(KEY, [Path(path).read_text().strip() for path in files])

    def test_only_target_mac_authorizes_ix(self):
        keys = evaluate('darwinConfigurations.darwin001.config.environment.etc."ssh/nix_authorized_keys.d/alan".text', raw=True)
        self.assertIn(KEY, keys)
        other = evaluate('darwinConfigurations.darwin002.config.users.users.amunozgo.openssh.authorizedKeys.keyFiles')
        self.assertNotIn(KEY, [Path(path).read_text().strip() for path in other])


if __name__ == "__main__":
    unittest.main(verbosity=2)
