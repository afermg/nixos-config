#!/usr/bin/env python3
"""Direct Raspberry Pi firmware boot backend for this host's NixOS bootspecs.

No partitioning, formatting, EEPROM updates, or U-Boot. Runtime installation
requires the exact Pi, HDD root, and mounted SD partition from policy.json.
Build-tree mode only creates a NEW directory (for the predeployment image).
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile

HEADER = '# Managed by nixos-config raspi4 direct boot.\n'
EXTENSION = 'org.afermg.raspi4.v1'


def digest(path):
    with Path(path).open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def run(*args):
    return subprocess.check_output([str(x) for x in args], text=True).strip()


def atomic_write(path, data):
    """Keep the old pointer intact until the replacement has been fsynced."""
    path = Path(path)
    fd, temp = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp, path)
        os.sync()
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def exclusive_copy(src, dst):
    with Path(src).open('rb') as inp, Path(dst).open('xb') as out:
        shutil.copyfileobj(inp, out)
        out.flush()
        os.fsync(out.fileno())
    if digest(src) != digest(dst):
        raise ValueError(f'Copy checksum mismatch: {dst}')


def load_generation(system):
    system = Path(system).resolve(strict=True)
    document = json.loads((system / 'boot.json').read_text())
    spec = document['org.nixos.bootspec.v1']
    extra = document[EXTENSION]
    if spec['system'] != 'aarch64-linux':
        raise ValueError('Only aarch64-linux is supported')
    if Path(spec['toplevel']).resolve() != system or spec['init'] != str(system / 'init'):
        raise ValueError('Bootspec does not describe the requested system')
    if 'initrdSecrets' in spec:
        raise ValueError('Secrets in a FAT initrd are deliberately unsupported')
    if document.get('org.nixos.specialisation.v1'):
        raise ValueError('Specialisation selection is not implemented by this backend')
    params = spec['kernelParams']
    if not isinstance(params, list) or not all(isinstance(x, str) and not any(c in x for c in '\n\r\x00') for x in params):
        raise ValueError('Invalid kernel command line')
    with Path(spec['kernel']).open('rb') as f:
        header = f.read(64)
    if header[56:60] != b'ARM\x64':
        raise ValueError('Expected an uncompressed ARM64 Linux Image')
    files = {}
    for kind, source, suffix in [
        ('k', spec['kernel'], 'img'),
        ('i', spec['initrd'], 'img'),
        ('d', extra['dtb'], 'dtb'),
        ('a', extra['armstub'], 'bin'),
    ]:
        source = Path(source)
        checksum = digest(source)
        name = f'nixos/objects/{kind}-{checksum[:32]}.{suffix}'
        files[name] = {'source': str(source), 'sha256': checksum, 'size': source.stat().st_size}
    cmdline = ('init=' + spec['init'] + ' ' + ' '.join(params) + '\n').encode()
    checksum = hashlib.sha256(cmdline).hexdigest()
    cmd_name = f'nixos/objects/c-{checksum[:32]}.txt'
    files[cmd_name] = {'text': cmdline.decode(), 'sha256': checksum, 'size': len(cmdline)}
    names = {name.split('/')[-1][0]: name for name in files}
    config = HEADER + f'''[all]
arm_64bit=1
enable_gic=1
enable_uart=1
disable_overscan=1
avoid_warnings=1
auto_initramfs=0
camera_auto_detect=0
display_auto_detect=0
armstub={names['a']}
kernel={names['k']}
device_tree={names['d']}
initramfs {names['i']} followkernel
cmdline={cmd_name}
'''
    if any(len(line) >= 80 for line in config.splitlines()):
        raise ValueError('Firmware config line exceeds conservative 79-character limit')
    return {'system': str(system), 'label': spec['label'], 'files': files,
            'config': config, 'firmware': extra['firmware']}


def stage_objects(boot, generation, reserve=16 * 1024**2):
    boot = Path(boot)
    missing = []
    for name, meta in generation['files'].items():
        dst = boot / name
        if dst.exists():
            if not dst.is_file() or digest(dst) != meta['sha256']:
                raise ValueError(f'Existing boot object is corrupt or unexpected: {dst}')
        else:
            missing.append((dst, meta))
    if shutil.disk_usage(boot).free < sum(meta['size'] for _, meta in missing) + reserve:
        raise ValueError('Insufficient SD space; existing default has NOT been changed')
    (boot / 'nixos/objects').mkdir(parents=True, exist_ok=True)
    for dst, meta in missing:
        if 'text' in meta:
            atomic_write(dst, meta['text'].encode())
        else:
            fd, temp = tempfile.mkstemp(prefix='.object-', dir=dst.parent)
            os.close(fd)
            try:
                with Path(meta['source']).open('rb') as inp, open(temp, 'wb') as out:
                    shutil.copyfileobj(inp, out)
                    out.flush()
                    os.fsync(out.fileno())
                if digest(temp) != meta['sha256']:
                    raise ValueError(f'Staged object checksum mismatch: {dst}')
                os.replace(temp, dst)
            finally:
                if os.path.exists(temp):
                    os.unlink(temp)
    for name, meta in generation['files'].items():
        if digest(boot / name) != meta['sha256']:
            raise ValueError(f'Final boot object verification failed: {name}')
    os.sync()


def check_target(policy):
    if os.geteuid() != 0:
        raise ValueError('Runtime boot installation requires root')
    if b'Raspberry Pi 4 Model B' not in Path('/proc/device-tree/model').read_bytes():
        raise ValueError('Not the target Raspberry Pi model')
    addresses = {p.read_text().strip() for p in Path('/sys/class/net').glob('*/address')}
    if policy['ethernetMac'] not in addresses:
        raise ValueError('Not the target Raspberry Pi Ethernet identity')
    boot = Path(policy['mountPoint'])
    if not boot.is_dir() or run('findmnt', '-nr', '-o', 'TARGET', '--target', boot) != str(boot):
        raise ValueError('SD boot partition is NOT mounted at the required mountpoint')
    if run('findmnt', '-nr', '-o', 'FSTYPE', '--target', boot) != 'vfat':
        raise ValueError('Boot mount is not FAT')
    source = run('findmnt', '-nr', '-o', 'SOURCE', '--target', boot)
    if not os.path.samefile(source, policy['bootDevice']):
        raise ValueError('Wrong boot device mounted; refusing all writes')
    root_source = run('findmnt', '-nr', '-o', 'SOURCE', '--target', '/')
    if not os.path.samefile(root_source, policy['rootDevice']):
        raise ValueError('Not running from the expected HDD root')
    if run('lsblk', '-dn', '-o', 'SERIAL', policy['hddDevice']) != policy['hddSerial']:
        raise ValueError('Wrong HDD serial')
    if run('blockdev', '--getsize64', policy['hddDevice']) != str(policy['hddBytes']):
        raise ValueError('Wrong HDD capacity')
    for name in ['pieeprom.upd', 'recovery.bin', 'autoboot.txt']:
        if (boot / name).exists():
            raise ValueError(f'Unexpected pending update/boot override: {name}')
    return boot


def ensure_recovery(boot, policy):
    """Preserve Raspberry Pi OS before replacing the normal firmware config."""
    recovery = boot / 'raspi4-recovery'
    recovery.mkdir(exist_ok=True)
    for name, expected in policy['recoveryHashes'].items():
        saved = recovery / name
        if not saved.exists():
            if digest(boot / name) != expected:
                raise ValueError(f'Original recovery file changed: {name}')
            exclusive_copy(boot / name, saved)
        if digest(saved) != expected:
            raise ValueError(f'Recovery backup checksum mismatch: {name}')
    # The original Pi OS cmdline must remain at its original path for recovery.
    if digest(boot / 'cmdline.txt') != policy['recoveryHashes']['cmdline.txt']:
        raise ValueError('Raspberry Pi OS cmdline was modified')
    active = (boot / 'config.txt').read_text()
    if not active.startswith(HEADER) and digest(boot / 'config.txt') != policy['recoveryHashes']['config.txt']:
        raise ValueError('Unknown default configuration; refusing to replace it')
    old_trial = recovery / 'nixos-bootstrap-tryboot.txt'
    if not old_trial.exists() and (boot / 'tryboot.txt').exists():
        exclusive_copy(boot / 'tryboot.txt', old_trial)
    # Standalone copies let Pi OS restore NixOS without a mounted Nix store.
    if 'helperDirectory' in policy:
        for name in ['bootloader.py', 'recovery.py']:
            data = (Path(policy['helperDirectory']) / name).read_bytes()
            target = recovery / name
            if not target.exists() or target.read_bytes() != data:
                atomic_write(target, data)
        data = (json.dumps(policy, indent=2) + '\n').encode()
        if not (recovery / 'policy.json').exists() or (recovery / 'policy.json').read_bytes() != data:
            atomic_write(recovery / 'policy.json', data)
    return (recovery / 'config.txt').read_bytes()


def state_record(generation):
    return {k: generation[k] for k in ['system', 'label', 'files', 'config']}


def generation_key(system):
    key = Path(system).name.split('-', 1)[0]
    if not re.fullmatch('[a-z0-9]{32}', key):
        raise ValueError('Not a Nix store generation')
    return key


def pin_generation(system, gc_dir):
    gc_dir.mkdir(parents=True, exist_ok=True)
    link = gc_dir / generation_key(system)
    if not link.is_symlink() and not link.exists():
        link.symlink_to(system)
    if not link.is_symlink() or str(link.resolve()) != system:
        raise ValueError(f'Unexpected GC root: {link}')


def install_generation(boot, generation, policy, gc_dir, booted):
    """Transactional core; caller must hold the lock and verify the live target."""
    recovery_config = ensure_recovery(boot, policy)
    state_path = boot / 'nixos/state.json'
    previous = json.loads(state_path.read_text()) if state_path.exists() else {'generations': []}
    if not isinstance(previous.get('generations'), list):
        raise ValueError('Invalid boot history')
    for g in previous['generations']:
        if not isinstance(g, dict) or not isinstance(g.get('files'), dict) or not isinstance(g.get('system'), str):
            raise ValueError('Invalid generation in boot history')
        generation_key(g['system'])
    stage_objects(boot, generation)
    pin_generation(generation['system'], gc_dir)
    history = [state_record(generation)] + [g for g in previous['generations'] if g['system'] != generation['system']]
    retained = history[:policy['retain']]
    for g in history[policy['retain']:]:
        if g['system'] == str(booted):
            retained.append(g)
    # Keep the firmware-native recovery config too; initiating tryboot requires
    # the vendor kernel. The portable raspi4-recovery helper switches config.txt.
    atomic_write(boot / 'tryboot.txt', recovery_config)
    atomic_write(boot / 'config.txt', generation['config'].encode())
    atomic_write(state_path, (json.dumps({'generations': retained}, indent=2) + '\n').encode())
    # Cleanup follows commit. Never touch firmware, recovery, or other files.
    needed = {name for g in retained for name in g['files']}
    for path in (boot / 'nixos/objects').iterdir():
        if path.is_file() and not path.is_symlink() and str(path.relative_to(boot)) not in needed:
            path.unlink()
    retained_systems = {g['system'] for g in retained}
    for link in gc_dir.iterdir():
        if link.is_symlink() and str(link.resolve()) not in retained_systems:
            link.unlink()
    os.sync()
    if (boot / 'config.txt').read_text() != generation['config']:
        raise ValueError('Default config readback failed')
    print(f"Installed direct SD boot: {generation['system']}")
    print(f"Retained {len(retained)} generations; Raspberry Pi OS recovery: sudo ix-recovery")


def install(system, policy):
    if Path(system).resolve().parent != Path('/nix/store'):
        raise ValueError('Runtime installation requires a Nix store system closure')
    if policy['retain'] < 1:
        raise ValueError('Must retain at least the new default generation')
    check_target(policy)
    generation = load_generation(system)
    with open('/run/lock/raspi4-boot.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        # Recheck after taking the lock, before any filesystem changes.
        boot = check_target(policy)
        install_generation(boot, generation, policy,
                           Path('/nix/var/nix/gcroots/raspi4-boot'),
                           Path('/run/booted-system').resolve())


def build_tree(system, output):
    output = Path(output)
    if output.exists():
        raise ValueError('build-tree requires a NEW output directory')
    generation = load_generation(system)
    output.mkdir(parents=True)
    stage_objects(output, generation)
    firmware = Path(generation['firmware'])
    for pattern in ['bootcode.bin', 'start*.elf', 'fixup*.dat']:
        matches = sorted(firmware.glob(pattern))
        if not matches:
            raise ValueError(f'Missing firmware: {pattern}')
        for src in matches:
            exclusive_copy(src, output / src.name)
    atomic_write(output / 'config.txt', generation['config'].encode())
    atomic_write(output / 'manifest.json', (json.dumps(state_record(generation), indent=2) + '\n').encode())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('install')
    p.add_argument('--system', required=True)
    p.add_argument('--policy', required=True)
    p = sub.add_parser('build-tree')
    p.add_argument('--system', required=True)
    p.add_argument('--output', required=True)
    args = parser.parse_args()
    if args.command == 'install':
        install(args.system, json.loads(Path(args.policy).read_text()))
    else:
        build_tree(args.system, args.output)


if __name__ == '__main__':
    main()
