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
