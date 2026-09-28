#!/usr/bin/env python3
"""Select Raspberry Pi OS recovery or restore NixOS without kernel reboot flags.

The upstream NixOS kernel ignores the Raspberry Pi-specific tryboot argument.
Recovery therefore selects the saved Pi OS config persistently. From Pi OS:
  sudo python3 /boot/firmware/raspi4-recovery/recovery.py restore --reboot
Use --previous to select the previous retained NixOS generation instead.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess

from bootloader import HEADER, atomic_write, check_target, digest


def select(boot, policy):
    recovery = boot / 'raspi4-recovery'
    current = (boot / 'config.txt').read_bytes()
    if not current.startswith(HEADER.encode()):
        raise ValueError('Default is not a managed NixOS configuration')
    for name, expected in policy['recoveryHashes'].items():
        if digest(recovery / name) != expected:
            raise ValueError(f'Invalid recovery backup: {name}')
    if digest(boot / 'cmdline.txt') != policy['recoveryHashes']['cmdline.txt']:
        raise ValueError('Recovery command line was modified')
    for name in ['kernel8.img', 'initramfs8', 'bcm2711-rpi-4-b.dtb', 'start4.elf', 'fixup4.dat']:
        if not (boot / name).is_file():
            raise ValueError(f'Missing Raspberry Pi OS recovery asset: {name}')
    atomic_write(recovery / 'return-config.txt', current)
    atomic_write(boot / 'config.txt', (recovery / 'config.txt').read_bytes())
    print('Raspberry Pi OS is selected; no kernel-specific reboot flags are needed.')
    print('From Pi OS: sudo python3 /boot/firmware/raspi4-recovery/recovery.py restore --reboot')


def restore(boot, policy, previous=False):
    recovery = boot / 'raspi4-recovery'
    if digest(boot / 'config.txt') != policy['recoveryHashes']['config.txt']:
        raise ValueError('Default is not the verified Raspberry Pi OS recovery config')
    state = json.loads((boot / 'nixos/state.json').read_text())
    generations = state['generations']
    if previous:
        if len(generations) < 2:
            raise ValueError('No previous generation retained')
        generation = generations[1]
    else:
        returning = (recovery / 'return-config.txt').read_text()
        generation = next((g for g in generations if g['config'] == returning), None)
        if generation is None:
            raise ValueError('Saved return config does not match a retained generation')
    if not generation['config'].startswith(HEADER):
        raise ValueError('Unknown NixOS configuration format')
    for name, meta in generation['files'].items():
        path = boot / name
        if not path.resolve().is_relative_to((boot / 'nixos/objects').resolve()):
            raise ValueError('Unsafe object path in generation metadata')
        if digest(path) != meta['sha256']:
            raise ValueError(f'NixOS boot asset checksum mismatch: {name}')
    atomic_write(boot / 'config.txt', generation['config'].encode())
    print('Restored NixOS default:', generation['system'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['select', 'restore'])
    parser.add_argument('--policy', default=str(Path(__file__).parent / 'policy.json'))
    parser.add_argument('--previous', action='store_true')
    parser.add_argument('--reboot', action='store_true')
    args = parser.parse_args()
    policy = json.loads(Path(args.policy).read_text())
    if args.command == 'restore':
        policy = policy | {'mountPoint': '/boot/firmware', 'rootDevice': policy['recoveryRootDevice']}
    elif args.previous:
        parser.error('--previous applies only to restore')
    with open('/run/lock/raspi4-boot.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        boot = check_target(policy)
        if args.command == 'select':
            select(boot, policy)
        else:
            restore(boot, policy, args.previous)
        os.sync()
    if args.reboot:
        subprocess.run(['systemctl', 'reboot'], check=True)


if __name__ == '__main__':
    main()
