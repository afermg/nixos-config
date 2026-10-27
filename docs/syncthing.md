# Inspecting Syncthing manually

The Syncthing management interface is intentionally bound to
`127.0.0.1:8384` on every configured host. Do not expose it on a Tailscale or
public address; use the local interface or an SSH tunnel.

## Inspect the local host

Open the following address in a browser on the machine running Syncthing:

```text
http://127.0.0.1:8384
```

On Linux, confirm that the user service is running first:

```bash
systemctl --user status syncthing.service
```

Useful read-only CLI checks are:

```bash
syncthing cli show system
syncthing cli show connections
syncthing cli config folders list
```

## Inspect `moby` from another computer

Because the GUI listens only on `moby`'s loopback interface, forward it through
SSH over Tailscale. Run this on the local computer and leave the command
running:

```bash
ssh -o ExitOnForwardFailure=yes -N \
  -L 8385:127.0.0.1:8384 \
  amunoz@moby.tail5e510f.ts.net
```

Then open:

```text
http://127.0.0.1:8385
```

Port `8385` is deliberately used on the local side so it does not conflict with
a local Syncthing GUI on port `8384`. Choose another unused local port if
necessary. Press `Ctrl-C` in the SSH terminal to close the tunnel.

## What to check in the GUI

1. Confirm the expected **Remote Devices** are connected. An offline laptop is
   not necessarily an error; changes remain queued until it reconnects.
2. Confirm each relevant folder says **Up to Date**.
3. Open a folder and compare **Local State** with **Global State**.
4. Inspect **Out of Sync Items**, **Failed Items**, and **Recent Changes** when
   counts differ or synchronization appears stalled.
5. Verify the folder ID and local path before diagnosing the wrong directory.

Folder and device definitions are declarative. Make lasting changes in:

- `modules/shared/config/syncthing/sync.nix` for `moby`
- `modules/shared/config/syncthing/receiver.nix` for receiving hosts
- `homes/ix/syncthing.nix` for ix's paused migration folders
- `modules/shared/config/syncthing/ix-backups.nix` for the encrypted backup mesh
  (each host must explicitly select its existing `ixBackupMesh.deviceName`)

On ix, `documents` and `pi-sessions` remain paused receive-only working copies.
`ix-backups` is now an active send-only folder. Receivers use receive-only mode,
prefer smaller snapshots, and retain remote deletions indefinitely in trashcan
versioning. The folder carries only closed encrypted artifacts: legacy
`ix-state-*.tar.zst.age` archives and hourly `ix/measurements/` snapshots, never
live databases or credential directories. There is no automatic archive pruning.

Data listeners and peer addresses use Tailscale DNS on TCP 22000; discovery,
relays and NAT traversal are disabled. The management GUI stays on loopback.
Device keys/IDs are preserved, not generated or copied from another host.

As of 2026-10-15, ix and Oppy are operational. One measurement artifact has been
received through Syncthing and decrypted/integrity-checked on Oppy. A historical
multi-GB archive backlog is a separate transfer: a connected peer or one verified
snapshot does **not** mean the whole folder or all other mesh peers are up to date.
Other receivers still need live identity/acceptance checks and activation.
See [the measurement backup and restore notes](../machines/ix/HOME_ASSISTANT_BACKUP.md).

Do not rely on changes made only in the web interface. In particular,
`overrideFolders = true` and `overrideDevices = true` on `moby` cause the Nix
configuration to replace interactive folder and device changes at activation.

## Troubleshooting on `moby`

```bash
systemctl --user restart syncthing.service
journalctl --user -u syncthing.service --since "15 minutes ago"
```

After editing the declarative configuration, activate the relevant Home Manager
configuration before expecting the GUI to reflect the change.
