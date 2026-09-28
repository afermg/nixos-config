# ix roadmap

This roadmap applies **only to ix**. It is not a general nixos-config backlog.

## Storage and recovery

- [ ] Evaluate ZFS for ix: data-only datasets versus root-on-ZFS, ARM/kernel
  compatibility, memory/ARC limits on the 8 GB Pi, and USB-HDD reliability.
  ix currently uses ext4 on the WD HDD; the SD firmware partition is FAT.
- [ ] If ZFS is chosen, plan a backed-up, verified migration/reinstallation.
  There is no in-place ext4-to-ZFS conversion. Do not format the only working
  copy, discard Pi OS recovery, or enable unsupported HDD discard/autotrim.
- [ ] Add and restore-test independent backups for ix's data and private state.
  Syncthing working copies are not backups.
- [ ] Revisit the Samsung NVMe/enclosure zero-capacity issue before considering
  it as alternative storage for ix; do not assume either component is healthy.

## Memory service

- [ ] Decide how ix should access Hindsight while moby is off: a supported local
  deployment within ix's resource limits, or a separately available server.
- [ ] If relocating Hindsight, use its supported backup/restore procedure and
  verify queries/retention. Never synchronize a live database with Syncthing.

## Network and relay services

- [ ] Move pi-msg relay duties from moby to ix, including secrets, account
  registration policy, service health checks, and rollback to the current relay
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
