# ix handoff — 2026-09-28

## Server

- Hostname and flake entry: **ix**; branch: **ix-migration**.
- Normal access: **ix.tail5e510f.ts.net**, through the manually approved Tailscale
  node. SSH remains key-only with the separately verified NixOS host pin.
- Raspberry Pi 4B / 8 GB. Direct SD firmware/kernel boot; **ext4** WD HDD root.
  ZFS is not enabled on ix. Its evaluation/migration is in [ROADMAP.md](ROADMAP.md).
- Raspberry Pi OS recovery remains on the SD. Real recovery/return and NixOS
  rollback/reapplication tests passed before application migration.
- Systems and FAT artifacts were built and checked on moby before deployment;
  neither drive was flashed or reformatted during permanent deployment.

See [README.md](README.md) for access/build/recovery commands and
[MAINTENANCE_LOG.md](MAINTENANCE_LOG.md) for the detailed history. The latest
system/image paths and reboot receipts are stored privately in
`~/.local/state/raspi4-deployment/` on ix.

## Workspace

- **Your shared Emacs configuration**, with Meow, Vertico, Magit, the Pi LLM
  dashboard, and Ghostel; native tools installed through Nix. Straight sources
  were copied without x86 native modules. Ghostel downloaded its ARM module;
  its native Fish shell passed an execution check.
- **Fish** as login shell, with your shared Pure, autopair, fishbang,
  fish-you-should-use, sponge, and async-prompt plugins.
- Google Calendar integration/timer/agenda entry removed; existing personal
  calendar files and credentials preserved rather than deleted.
- Git/LFS, Node/npm (user prefix `~/.local`), Pi 0.85.1. A local offline npm
  install/run/uninstall and a tool-free provider inference check passed.
- No full desktop home profile, moby-dependent Hindsight client, private SSH
  key, or signing/decryption identity was imported.

Run `emacsclient -t`, `M-x mu4e` for mail, or `C-c L` / `M-x ix-pi` for the
shared agent dashboard. A plain `pi` terminal session also works.

## Mail and data

Three accounts passed TLS IMAP/SMTP authentication; Purdue OAuth renewal works
locally. Native isync explicitly includes XOAUTH2 support. Six channels / 36
mailboxes completed successfully before the editor expansion; the native index
contained 38,988 messages at cutover. No live mu database was copied.
The expanded archive-import pipeline also completed: 59/25/7 new Purdue/Broad/
Broad-spam imports, zero errors. The operator explicitly waived further mail-
timer investigation after the last post-reboot probe found it inactive.

Mail, mirror cache, Documents, and 695 session files were copied and checksum-
verified from an immutable moby checkpoint, without deleting originals. Fifteen
legacy-owned Documents files needed a privileged reader, not permission changes.
The last Documents reconciliation found no post-checkpoint changes. Symlinks
were preserved, not followed into unrelated datasets; working copies are not
backups.

The archive importer's separate SQLite receipt database was subsequently copied
using SQLite's consistent backup API, integrity-checked, and checksum-verified.
The shared mail workflow uses the local scoped password files and Pi-only GPG
OAuth key, not a cloned vault. Source account directions and the shared
Trash-only, explicit-confirmation deletion safeguards are retained.

The requested device-ID email was **sent to alan@quasimorphic.com and verified
in the Inbox**, without marking it read. The identifier was removed from the
repository documents. Runtime credentials and identifiers are not Git content
or Syncthing folders.

## Services and deferred work

Home Assistant is **fresh and minimal**, with no imported accounts/Roborock
state. Onboarding is available through an SSH tunnel to loopback port 8123.
The accepted loopback listener persisted across reboot. Moby's original
controller data remains intact.

Syncthing uses its own identity and **Tailscale-only transport with DNS names**.
Public/local discovery and relays remain disabled. Its password-protected GUI
is on loopback port 8384; username `amunoz`, password stored privately at
`~/.config/raspi4-secrets/syncthing-gui-password`. Documents/session folders stay
paused and receive-only pending the explicitly deferred Mac reconciliation.
That work does not block shutdown.

[ROADMAP.md](ROADMAP.md) is exclusively for ix: ZFS evaluation, independent
backups, Hindsight, Mac synchronization, ix code cleanup, and fresh HA onboarding.
Hindsight's database stays on moby; its API is unavailable while moby is off.
The Samsung NVMe/enclosure remains an unresolved separate storage option.

## Preservation and shutdown

The repository, dirty working tree, bundles, boot backup, and verification
receipts are saved on ix under `~/.local/share/src/nixos-config` and privately
under `~/.local/state/raspi4-deployment/`. Changes remain **uncommitted** on
`ix-migration`, with a recoverable bundle/overlay; unrelated work is preserved.
No remote push or blanket staging was performed.

Legacy `raspi4` runtime paths/boot identifiers remain only where needed for
credential, lock, and rollback compatibility; they are not the server hostname.
The latest real boot was `5b4f7c4d-6987-4489-933d-ff8223355d70`, with hostname
ix and matching current/booted system paths; final checks are in the log.

Moby is shut down only after the final checks and handoff. The private
`moby-shutdown-status.json` records the request/observation separately; scheduling
shutdown is not claimed as already observing power-off.
