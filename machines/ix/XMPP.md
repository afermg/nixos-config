# ix XMPP operations

The server is Tailscale-only at `ix.tail5e510f.ts.net`: XMPP STARTTLS on5222,
HTTPS upload on5443. Certificates must pass hostname and system-CA verification.
Do not bypass TLS verification, reset accounts, or copy another host's identity.

## Supervision

`machines/ix/ejabberd.nix` adds ix-only `Restart=on-failure`, with30-second backoff
and at most three starts per10-minute window. This replaces the prior default
`Restart=no`; it does not endlessly retry database corruption.

`ix-xmpp-health.timer` checks every five minutes (up to15seconds jitter). Its
unprivileged, read-only probe verifies required STARTTLS, trusted served
certificates with at least seven days remaining, SCRAM-SHA-256 advertisement,
and an HTTPS response on5443. No credentials, messages, restarts, database writes
or automatic repairs are performed by the probe. A healthy404 from `/upload`
without an upload slot is expected. Timeout/certificate/protocol/5xx failures
produce a failed systemd unit and a JSON diagnostic in the journal.

```sh
systemctl status ejabberd.service ix-xmpp-health.service ix-xmpp-health.timer
systemctl --failed
journalctl -u ejabberd.service -u ix-xmpp-health.service
```

These are local health checks, **not an off-host alert**. They cannot run through
a kernel/network/storage hang. After the restart limit, investigate instead of
blindly resetting the limit or repeatedly restarting.

## Recovery completed 2026-10-08

Ejabberd failed to open `last_activity.DAT` (`not_a_dets_file`). All other DETS
files passed bounded read-only opens. Four accounts and51 archived messages were
intact. A file already recovered into `/lost+found/#83308405` contained four
historical `last_activity` records for this domain. Their keys matched the
existing archive (also roster/vCard evidence), not the currently registered user
keys; they were validated as historical presence metadata, not used to alter
current accounts.

The recovered file was repaired and validated in a temporary working file. With
ejabberd stopped and guarded against concurrent startup, only `last_activity.DAT`
was restored. All other DAT files were byte-identical before startup. Existing
recovered originals and the corrupt file were retained; no new application-data
backup/archive was made. Accounts, roster, messages, cookies and TLS keys were
not reset. The original corrupt file is under the private
`/var/lib/ejabberd/recovery-evidence/` directory. Do not rerun recovery just because
historical logs still contain the old fatal error.

Startup succeeded; independent TLS checks of5222/5443 passed, and two existing
clients authenticated. That is stronger than a systemd-active check, but is not a
forced crash/restart test or a guarantee of future availability.

The checks since Atuin removal have shown **no new ext4/USB/I/O faults**. This
outage was blocked by pre-existing table corruption, not fresh corruption or
evidence of an ongoing hardware failure. Atuin removal appears to have stabilized
the system, although causation is not established. If new faults occur, stop expansion/restart loops and address
that path. Never run filesystem repair on a mounted disk. Preserve originals;
do not reset Mnesia or discard the message/account databases.

Private repair/build/activation evidence on Oppy:
`~/.local/state/ix-xmpp-repair-20261008/`.

The subsequent room-specific manual-ownership and brightness-slider update is
documented in [LIGHTING.md](LIGHTING.md). It preserves the XMPP service and policy.
