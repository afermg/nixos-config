"""Regression checks for Moby's post-evacuation storage and boot policy.

These inspect configuration only: they never format, import, or remove a device.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class OffloadPolicyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.disko = (ROOT / 'disko.nix').read_text()
        cls.boot = (ROOT / 'boot.nix').read_text()
        cls.module = (ROOT / 'ssd-offload.nix').read_text()
        cls.runtime = (ROOT / 'ssd-offload-runtime.sh').read_text()

    def test_only_retained_ssd_and_both_hdds_are_declared(self):
        devices = re.findall(r'device\s*=\s*"([^"]+)"', self.disko)
        self.assertEqual(devices, [
            '/dev/disk/by-id/nvme-eui.002538414144b5fb',
            '/dev/disk/by-id/wwn-0x5000c500e84abb69',
            '/dev/disk/by-id/wwn-0x5000c500e86adcbe',
        ])
        self.assertNotRegex(self.disko, r'(?m)^\s*ssd1\s*=')

    def test_retained_ssd_keeps_existing_esp(self):
        ssd = self.disko.split('# Former ssd1', 1)[0]
        self.assertIn('ESP = {', ssd)
        self.assertIn('type = "EF00";', ssd)
        self.assertIn('mountpoint = "/boot";', ssd)
        self.assertIn('pool = "zroot";', ssd)

    def test_grub_does_not_need_to_read_root_pool(self):
        self.assertIn('copyKernels = true;', self.boot)
        self.assertIn('efiInstallAsRemovable = true;', self.boot)
        self.assertIn('path = "/boot";', self.boot)

    def test_force_import_all_hook_removed(self):
        self.assertNotIn('importzfsandchmod', self.boot)
        self.assertNotIn('zpool import -fa', self.boot + self.runtime)
        self.assertNotIn('chmod 0777 /datastore', self.boot)
        self.assertIn('imports = [ ./ssd-offload.nix ];', self.boot)

    def test_only_identified_hdd_pool_is_imported(self):
        self.assertIn('pool_guid=10870576030707066749', self.runtime)
        self.assertIn('zpool import -N -o cachefile=none -d /dev/disk/by-id "$pool_guid"', self.runtime)
        self.assertIn('guid zstore) == "$pool_guid"', self.runtime)
        self.assertNotRegex(self.runtime, r'zpool (?:clear|upgrade|remove|detach|destroy)\b')

    def test_port_selection_uses_wwns_not_sda_host0(self):
        self.assertIn('for wwn in 0x5000c500e84abb69 0x5000c500e86adcbe', self.runtime)
        self.assertIn('/dev/disk/by-id/wwn-$wwn', self.runtime)
        self.assertIn('max_performance', self.runtime)
        self.assertNotIn('/host0/', self.runtime)
        self.assertNotIn('/host1/', self.runtime)

    def test_offload_is_explicitly_mounted(self):
        self.assertIn('what = "zstore/ssd-migration/bulk";', self.module)
        self.assertIn('where = "/srv/ssd-offload";', self.module)
        self.assertIn('requires = [ importUnit ];', self.module)
        self.assertIn('after = [ importUnit ];', self.module)
        self.assertIn('before = [ "local-fs.target" ];', self.module)
        self.assertIn('wantedBy = [ "local-fs.target" ];', self.module)

    def test_legacy_datastore_is_not_automounted(self):
        datastore = self.disko.split('datastore = {', 1)[1]
        self.assertIn('options.canmount = "noauto";', datastore)
        self.assertIn('canmount zstore/datastore) == noauto', self.runtime)
        self.assertNotIn('zfs mount -a', self.runtime)
        self.assertNotIn('zpool import -a', self.runtime)

    def test_runtime_requires_exact_destination_purpose(self):
        self.assertIn('org.quasimorphic:purpose "$dataset") == ssd-folder-offload', self.runtime)
        self.assertIn('mountpoint "$dataset") == /srv/ssd-offload', self.runtime)
        self.assertIn('canmount "$dataset") == noauto', self.runtime)


if __name__ == '__main__':
    unittest.main()
