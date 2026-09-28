# ix roadmap

This roadmap applies **only to ix**. It is not a general nixos-config backlog.

## Storage and recovery

- [ ] Evaluate ZFS for ix: data-only datasets versus root-on-ZFS, ARM/kernel
  compatibility, memory/ARC limits on the 8 GB Pi, and USB-HDD reliability.
  ix currently uses ext4 on the WD HDD; the SD firmware partition is FAT.
- [ ] If ZFS is chosen, plan a backed-up, verified migration/reinstallation.
  There is no in-place ext4-to-ZFS conversion. Do not format the only working
  copy, discard Pi OS recovery, or enable unsupported HDD discard/autotrim.
- [x] Add independent encrypted backups for ix's selected data and private
  state. `ix-state-backup.timer` writes verified archives under
  `~/.local/share/syncthing/ix-backups/ix`; Syncthing working copies remain
  non-backups.
- [x] Restore-test the first `ix-state-*.tar.zst.age` archive enough to verify
  checksum, host-key decryption, tar listing, and representative Pi/Elfeed/org
  and Syncthing identity paths.
- [ ] Revisit the Samsung NVMe/enclosure zero-capacity issue before considering
  it as alternative storage for ix; do not assume either component is healthy.

## Memory and reader services

- [x] Decide how ix should access Hindsight while moby is off: ix now owns the
  REST API, restored database path, token file, backup unit, and Pi client URL.
  The API is gated until a dedicated `~/.local/state/hindsight-codex/auth.json`
  exists because the upstream local embedding stack crashes on the Pi 4 CPU.
- [ ] Finish Hindsight activation after the dedicated Codex login, then verify
  recall queries, restore-test the first ix archive, and only then revisit
  retention/extraction workers. Never synchronize a live database with
  Syncthing.
- [x] Migrate Elfeed to ix so RSS state remains available when moby is off.
  ix has the copied database, 779 configured feeds after opening Elfeed, and a
  pre-copy backup under `~/.local/state/ix-migration/backups/`.

## Network and relay services

- [x] Move pi-msg relay configuration from moby to ix: ix has its own encrypted
  config, Tailscale-only ejabberd module, account-registration helper, and a
  marker-gated user service so it does not churn before accounts exist.
- [ ] Complete pi-msg owner account registration on ix, verify phone and bot
  login against `ix.tail5e510f.ts.net`, then keep the moby secret as rollback
  until ix is verified as the stable endpoint.
- [ ] Add Pi-hole capabilities on ix for private tailnet DNS/ad blocking.
  Plan upstream DNS, Tailscale/DHCP integration, persistence, allow/deny-list
  backups, and a bypass/rollback path before changing clients.

## Mac synchronization

- [ ] Pair ix with the intended Macs, reconcile Documents and Pi sessions, then
  deliberately unpause the folders and choose their final direction/versioning.
- [ ] Retain Tailscale-only transport with peer DNS names; no public discovery
  or relay fallback. Keep device IDs in private operational records/email.
- [ ] Protect concurrent session writers and preserve conflicts. Never share
  agent auth, private keys, live mu indexes, or Hindsight's live database.

## ix configuration cleanup

- [ ] Consolidate ix's headless dependencies without importing the desktop home.
- [ ] Keep the shared Emacs/Fish configuration working on ARM and in a terminal;
  test active plugins and minimize ix-specific overrides.
- [ ] Retire legacy bootstrap names/state paths only with explicit migration and
  rollback/recovery tests. Do not rename existing recovery assets blindly.
- [ ] Review the direct-SD boot tooling for simplification without weakening
  hardware checks, asset validation, retained generations, or offline recovery.
- [ ] Complete fresh Home Assistant owner onboarding and declare only the
  integration dependencies actually selected for ix.
