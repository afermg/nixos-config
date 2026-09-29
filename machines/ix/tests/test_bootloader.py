"""Host-side bootloader tests. Never mount, format, reboot, or touch real /boot."""
import importlib.util
import json
from pathlib import Path
import tempfile
import subprocess
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('raspi_boot', Path(__file__).parents[1] / 'bootloader.py')
boot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boot)
sys.modules['bootloader'] = boot
recovery_spec = importlib.util.spec_from_file_location('raspi_recovery', Path(__file__).parents[1] / 'recovery.py')
recovery = importlib.util.module_from_spec(recovery_spec)
recovery_spec.loader.exec_module(recovery)


class BootloaderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.sd = self.root / 'sd'
        self.sd.mkdir()
        (self.sd / 'config.txt').write_text('arm_64bit=1\nauto_initramfs=1\n')
        (self.sd / 'cmdline.txt').write_text('root=PARTUUID=sd-recovery rootwait\n')
        (self.sd / 'tryboot.txt').write_text('kernel=nixos-sd-test/Image\n')
        (self.sd / 'unrelated.txt').write_text('keep me\n')
        self.original = (self.sd / 'config.txt').read_bytes()
        self.policy = {'retain': 2, 'helperDirectory': str(Path(__file__).parents[1]), 'recoveryHashes': {
            name: boot.digest(self.sd / name) for name in ['config.txt', 'cmdline.txt']}}
        self.gc = self.root / 'gc'
        self.sync = patch.object(boot.os, 'sync')
        self.sync.start()
        self.addCleanup(self.sync.stop)

    def system(self, key='a', different_kernel=False):
        system = self.root / (key * 32 + '-nixos-system-raspi4-test')
        system.mkdir()
        header = bytearray(64)
        header[56:60] = b'ARM\x64'
        (system / 'Image').write_bytes(header + (key if different_kernel else 'kernel').encode())
        (system / 'initrd').write_bytes(b'initrd')
        (system / 'dtb').write_bytes(b'matching-dtb')
        (system / 'armstub').write_bytes(b'armstub')
        (system / 'init').write_bytes(b'init')
        firmware = system / 'firmware'
        firmware.mkdir()
        for name in ['bootcode.bin', 'start4.elf', 'fixup4.dat']:
            (firmware / name).write_bytes(name.encode())
        doc = {
            'org.nixos.bootspec.v1': {
                'toplevel': str(system), 'init': str(system / 'init'),
                'kernel': str(system / 'Image'), 'initrd': str(system / 'initrd'),
                'kernelParams': ['console=tty0', 'root=fstab'],
                'system': 'aarch64-linux', 'label': 'test',
            },
            boot.EXTENSION: {
                'dtb': str(system / 'dtb'), 'armstub': str(system / 'armstub'),
                'firmware': str(firmware),
            },
        }
        (system / 'boot.json').write_text(json.dumps(doc))
        return system

    def install(self, system, booted=None):
        g = boot.load_generation(system)
        boot.install_generation(self.sd, g, self.policy, self.gc, booted or system)
        return g

    def test_first_install_preserves_recovery_and_switches_default(self):
        g = self.install(self.system())
        self.assertEqual((self.sd / 'tryboot.txt').read_bytes(), self.original)
        self.assertEqual((self.sd / 'raspi4-recovery/config.txt').read_bytes(), self.original)
        self.assertEqual((self.sd / 'config.txt').read_text(), g['config'])
        self.assertEqual((self.sd / 'unrelated.txt').read_text(), 'keep me\n')
        self.assertEqual((self.sd / 'raspi4-recovery/nixos-bootstrap-tryboot.txt').read_text(), 'kernel=nixos-sd-test/Image\n')
        self.assertTrue((self.gc / ('a' * 32)).is_symlink())
        self.assertTrue(all(len(line) < 80 for line in g['config'].splitlines()))

    def test_idempotent_install(self):
        system = self.system()
        self.install(system)
        names = sorted(p.name for p in (self.sd / 'nixos/objects').iterdir())
        self.install(system)
        state = json.loads((self.sd / 'nixos/state.json').read_text())
        self.assertEqual(len(state['generations']), 1)
        self.assertEqual(names, sorted(p.name for p in (self.sd / 'nixos/objects').iterdir()))

    def test_shared_kernel_is_deduplicated(self):
        self.install(self.system('a'))
        self.install(self.system('b'))
        self.assertEqual(len(list((self.sd / 'nixos/objects').glob('k-*'))), 1)
        self.assertEqual(len(list((self.sd / 'nixos/objects').glob('c-*'))), 2)

    def test_update_rollback_and_gc_preserve_booted_generation(self):
        a, b, c, d = [self.system(key, different_kernel=True) for key in 'abcd']
        self.install(a)
        self.install(b, a)
        self.install(c, a)
        state = json.loads((self.sd / 'nixos/state.json').read_text())
        self.assertEqual([g['system'] for g in state['generations']], list(map(str, [c, b, a])))
        self.install(d, c)
        self.assertFalse((self.gc / ('a' * 32)).exists())
        self.assertFalse((self.gc / ('b' * 32)).exists())
        self.assertEqual(len(list((self.sd / 'nixos/objects').glob('k-*'))), 2)
        self.install(c, d)
        self.assertEqual((self.sd / 'config.txt').read_text(), boot.load_generation(c)['config'])
        self.assertEqual((self.sd / 'tryboot.txt').read_bytes(), self.original)

    def test_unknown_original_config_is_not_overwritten(self):
        (self.sd / 'config.txt').write_text('foreign config\n')
        with self.assertRaisesRegex(ValueError, 'Original recovery file changed'):
            self.install(self.system())
        self.assertEqual((self.sd / 'config.txt').read_text(), 'foreign config\n')

    def test_changed_recovery_cmdline_is_rejected(self):
        a = self.system()
        self.install(a)
        previous = (self.sd / 'config.txt').read_bytes()
        (self.sd / 'cmdline.txt').write_text('changed\n')
        with self.assertRaisesRegex(ValueError, 'cmdline was modified'):
            self.install(a)
        self.assertEqual((self.sd / 'config.txt').read_bytes(), previous)

    def test_corrupt_cached_object_does_not_replace_default(self):
        a, b = self.system('a'), self.system('b')
        g = self.install(a)
        previous = (self.sd / 'config.txt').read_bytes()
        (self.sd / next(iter(g['files']))).write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'corrupt or unexpected'):
            self.install(b)
        self.assertEqual((self.sd / 'config.txt').read_bytes(), previous)

    def test_no_space_does_not_replace_default(self):
        with patch.object(boot.shutil, 'disk_usage', return_value=SimpleNamespace(free=0)):
            with self.assertRaisesRegex(ValueError, 'Insufficient SD space'):
                self.install(self.system())
        self.assertEqual((self.sd / 'config.txt').read_bytes(), self.original)

    def test_atomic_replace_failure_preserves_previous_file(self):
        with patch.object(boot.os, 'replace', side_effect=OSError('simulated failure')):
            with self.assertRaises(OSError):
                boot.atomic_write(self.sd / 'config.txt', b'new data')
        self.assertEqual((self.sd / 'config.txt').read_bytes(), self.original)
        self.assertFalse(list(self.sd.glob('.config.txt-*')))

    def test_runtime_rejects_non_store_path_before_target_inspection(self):
        with patch.object(boot, 'check_target') as check:
            with self.assertRaisesRegex(ValueError, 'Nix store system'):
                boot.install(self.root, self.policy)
        check.assert_not_called()

    def test_bad_architecture_and_initrd_secrets_are_rejected(self):
        system = self.system()
        doc = json.loads((system / 'boot.json').read_text())
        doc['org.nixos.bootspec.v1']['system'] = 'x86_64-linux'
        (system / 'boot.json').write_text(json.dumps(doc))
        with self.assertRaisesRegex(ValueError, 'aarch64'):
            boot.load_generation(system)
        doc['org.nixos.bootspec.v1']['system'] = 'aarch64-linux'
        doc['org.nixos.bootspec.v1']['initrdSecrets'] = 'do-not-run'
        (system / 'boot.json').write_text(json.dumps(doc))
        with self.assertRaisesRegex(ValueError, 'Secrets'):
            boot.load_generation(system)

    def test_build_tree_creates_new_image_tree_and_cannot_overwrite_sd(self):
        system = self.system()
        output = self.root / 'image-tree'
        boot.build_tree(system, output)
        self.assertTrue((output / 'start4.elf').is_file())
        self.assertTrue((output / 'manifest.json').is_file())
        self.assertTrue((output / 'config.txt').read_text().startswith(boot.HEADER))
        with self.assertRaisesRegex(ValueError, 'NEW output directory'):
            boot.build_tree(system, self.sd)
        self.assertEqual((self.sd / 'config.txt').read_bytes(), self.original)

    def test_invalid_history_does_not_replace_default(self):
        system = self.system()
        self.install(system)
        previous = (self.sd / 'config.txt').read_bytes()
        (self.sd / 'nixos/state.json').write_text('{"generations":[{}]}')
        with self.assertRaisesRegex(ValueError, 'Invalid generation'):
            self.install(system)
        self.assertEqual((self.sd / 'config.txt').read_bytes(), previous)

    def recovery_assets(self):
        for name in ['kernel8.img', 'initramfs8', 'bcm2711-rpi-4-b.dtb', 'start4.elf', 'fixup4.dat']:
            (self.sd / name).write_bytes(b'verified-original-recovery-asset')

    def test_portable_recovery_round_trip_without_reboot_flags(self):
        g = self.install(self.system())
        self.recovery_assets()
        recovery.select(self.sd, self.policy)
        self.assertEqual((self.sd / 'config.txt').read_bytes(), self.original)
        recovery.restore(self.sd, self.policy)
        self.assertEqual((self.sd / 'config.txt').read_text(), g['config'])

    def test_recovery_can_select_previous_generation(self):
        a, b = self.system('a'), self.system('b')
        ga = self.install(a)
        self.install(b, a)
        self.recovery_assets()
        recovery.select(self.sd, self.policy)
        recovery.restore(self.sd, self.policy, previous=True)
        self.assertEqual((self.sd / 'config.txt').read_text(), ga['config'])

    def test_restore_rejects_corruption_and_keeps_recovery_selected(self):
        g = self.install(self.system())
        self.recovery_assets()
        recovery.select(self.sd, self.policy)
        (self.sd / next(iter(g['files']))).write_bytes(b'corrupted')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            recovery.restore(self.sd, self.policy)
        self.assertEqual((self.sd / 'config.txt').read_bytes(), self.original)

    def test_recovery_selection_rejects_missing_vendor_assets(self):
        g = self.install(self.system())
        with self.assertRaisesRegex(ValueError, 'Missing Raspberry Pi OS'):
            recovery.select(self.sd, self.policy)
        self.assertEqual((self.sd / 'config.txt').read_text(), g['config'])

    def test_recovery_helper_is_standalone_on_sd(self):
        self.install(self.system())
        saved = self.sd / 'raspi4-recovery'
        self.assertTrue((saved / 'bootloader.py').is_file())
        self.assertEqual(json.loads((saved / 'policy.json').read_text()), self.policy)
        p = subprocess.run([sys.executable, str(saved / 'recovery.py'), '--help'],
                           capture_output=True, text=True, check=True)
        self.assertIn('--previous', p.stdout)


if __name__ == '__main__':
    unittest.main()
