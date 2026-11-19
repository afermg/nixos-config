# Moby SSD offload (2026-09-29)

## Upgrade verification — 2026-11-19

- Moby activated generation 322, NixOS `26.11.20261117.0490633`, without rebooting.
- Both pools reported ONLINE after the storage investigation and `zpool clear
  zstore`; historical errors are not proof that their underlying cause is fixed.
- The offload mount retained mount ID 107 throughout activation. Both offload
  services remained active; the legacy `zstore/datastore` was not mounted.
- The new kernel and initrd are installed on the existing ESP. Booting this
  generation remains unverified until a controlled reboot.
- Bridge helpers remain in place. Do not remove them or the evacuated SSD as
  part of an ordinary upgrade.

## Completed state

- All 13 selected folders passed rsync transfer checks, size/metadata comparison,
  and bounded sampled readback. Full checksum verification was deliberately
  replaced after the operator confirmed current recoverable backups elsewhere.
- At **14:00:10 EDT**, all original paths had been switched to HDD-backed symlinks
  and their retired SSD copies reclaimed. The paths are listed in
  `/var/lib/moby-ssd-offload/folders.txt`; inode-bound cutover/deletion receipts
  remain in `/var/lib/moby-ssd-offload/cutover/receipts`.
- SSD evacuation completed: **2026-09-29T14:41:16-04:00**.
- Read-only post-evacuation validation passed: **2026-09-29T14:44:17-04:00**.
- Current physical pool allocation: **2.99 TiB**;
  free: **0.63 TiB (17.5%)**.
- **Controlled reboot passed on 2026-09-29.** New boot ID:
  `330e6981-ed3e-46f9-acdd-00b74af2c449`. The retained SSD booted successfully,
  all 13 HDD-backed paths were readable, both SATA policies persisted, and no
  failed services or new storage errors were found.
- The evacuated SSD is **still physically installed**. Booting with it physically
  absent has not yet been tested. Never hot-unplug an NVMe SSD.
- Reboot evidence: `/home/amunoz/.local/state/ssd-offload/reboot-validation.json`.

## Storage identities — never rely on NVMe enumeration

- **Keep:** `nvme-eui.002538414144b5fb`, Samsung serial **`S7KGNJ0X158411M`**.
  Partition 1 is the EFI `/boot`; partition 2 is the sole active `zroot` vdev.
- **Evacuated:** `nvme-eui.002538414144b5f9`, serial **`S7KGNJ0X158409E`**.
  This disk has no ESP and is no longer an active pool member. Its labels were
  not wiped and it was not formatted. Do not re-add it to `zroot`.
- `zroot` GUID: `8526591754067295092`. Formerly a two-SSD stripe, now a single
  SSD plus ZFS indirect mapping metadata. `feature@device_removal` is active.
  Do **not** use `zpool detach` or run disko against the live installation.
- HDD `zstore` GUID: `10870576030707066749`. It remains a nonredundant stripe,
  not a backup. Existing `zstore/datastore` contents were not moved or deleted.
- `disko.nix` declares only the retained SSD, plus both HDDs using stable WWNs
  matching the existing `disk-hdd0-zfs` and `disk-hdd1-zfs` labels.

## HDD errors and mitigation

Initial copying produced SATA link resets and **5 read / 10 write errors**.
Since **08:47 EDT**, the two HDD ports use `max_performance` link power policy.
No additional storage errors were found by the final validation. This does not
prove the hardware fault is permanently fixed; cabling/power/controller issues
remain possible. Both HDDs and SSDs passed the final SMART gates.

At the September 29 handoff the HDD pool was deliberately still **DEGRADED**;
no `zpool clear` had been run. See the November 19 update above for current status.
The read/write counters naturally reset on reboot/import; pre-reboot counts are
preserved in `/var/lib/moby-ssd-offload/reboot-check-20260929/pools-before.txt`.
Investigate any new I/O errors before further storage changes. Earlier evidence
is in `/var/lib/moby-ssd-offload/{sata-guard,evacuation,post-evacuation}`.

## Persistent mount and future rebuilds

`boot.nix` imports `ssd-offload.nix`:

- `moby-sata-performance.service` resolves the two HDD WWNs to their current
  SATA ports and disables link power saving.
- `moby-ssd-offload-import.service` imports only the intended pool GUID with
  `-N`, without force-importing pools or mounting unrelated datasets.
- `srv-ssd\x2doffload.mount` mounts `zstore/ssd-migration/bulk` at
  `/srv/ssd-offload`. Copies are under `/srv/ssd-offload/home/amunoz`.
- Both that dataset and the legacy `zstore/datastore` have `canmount=noauto`.
  `/datastore` already contains unrelated SSD-root data and must not be covered.
- The underlying `/srv/ssd-offload` directory has mode `000`: if mounting fails,
  migrated symlinks fail rather than silently creating SSD fallback data.
- The mount is wanted, not required, by `local-fs.target`. The SSD root can boot
  without the HDD pool, but the migrated folders will then be unavailable.

Equivalent bridge units are installed under `/usr/local/lib/systemd/system`,
using `/var/lib/moby-ssd-offload/cutover/runtime.sh`. Actual unmount/remount and
boot-target dependency checks passed. At the September 29 handoff the new NixOS
source configuration was **evaluated, not switched**. The declarative units were
subsequently activated on November 19. Keep the bridge helper until the new
generation also passes reboot verification.

GRUB kernels and initrds reside on FAT ESP UUID **`E05C-4BE4`** on the retained
SSD, and were checksum-compared with the deployed generation after evacuation.
The source now explicitly sets `boot.loader.grub.copyKernels = true`. GRUB must
not need to read the root ZFS pool's indirect vdev mappings.

The current generation's older broad import activation hook remains until a
normal rebuild. The persistent `canmount=noauto` properties prevent it from
covering `/datastore` or automounting the offload dataset out of order. The new
source removes that hook entirely.

## Reboot result and physical removal

The controlled reboot and the following checks passed with both SSDs still
physically connected. Shut down, remove only the evacuated SSD identified below,
then boot with console/recovery access available and repeat these checks:

```sh
zpool status zroot zstore
findmnt /boot
findmnt /srv/ssd-offload
systemctl --failed
systemctl status moby-sata-performance moby-ssd-offload-import 'srv-ssd\x2doffload.mount'
```

`zroot` must have only `nvme-eui.002538414144b5fb-part2` as its active vdev, and all
13 home symlinks must resolve. Confirm both HDD link policies are still
`max_performance`. The SSD to disconnect while powered off is serial
**`S7KGNJ0X158409E`**. Confirm the next boot with that SSD physically absent.
Do not remove serial `S7KGNJ0X158411M`, which holds both root data and the ESP.
