# Home Assistant backups

## Active measurement backup (2026-10-15)

`ix-measurement-backup.timer` runs hourly with up to two minutes of jitter and
catches missed runs after boot. It uses SQLite's online backup API against the
read-only Recorder source, checks the standalone snapshot's full integrity, then
compresses and age-encrypts it. Plaintext stays in a private `/run` directory.
Completed ciphertext and its checksum are atomically published under:

```text
/home/amunoz/.local/share/syncthing/ix-backups/ix/measurements/
```

Publication uses Linux `O_TMPFILE` in the destination mount: encrypted staging
has no visible name until complete. This preserves the strict filesystem sandbox
without cross-bind-mount hard links or partially synchronized archives. Names are
append-only; there is no automatic archive pruning. Capture is limited to 512 MiB
and a three-minute service deadline, with idle I/O and a 768 MiB memory limit.

The `ix-backups` folder is send-only on ix and receive-only on its mesh receivers.
Oppy is enrolled and running. The first snapshot was received **through Syncthing**
and independently decrypted on Oppy; its manifest/checksum matched and SQLite's
full integrity check passed (1,020 states, all 11 streams). This is a disposable
restore check, not replacement of the live database. Legacy archive transfers and
other receivers have separate completion status; do not infer full mesh completion.

Encryption uses the personal SSH recipient and a dedicated recovery recipient.
Keep the recovery private key separately/offline, never on ix or in the shared
folder. Do not synchronize live SQLite files, WALs or controller directories.

```bash
systemctl status ix-measurement-backup.service ix-measurement-backup.timer
journalctl -u ix-measurement-backup.service --no-pager -n 20
```

Check the receiver GUI's pending/failed items too. The publisher deliberately logs
`replication_verified=false`: local success cannot establish remote delivery.
For a restore check, verify the `.sha256`, decrypt/decompress into private temporary
RAM storage, check both manifest hashes and `PRAGMA integrity_check` on the closed
SQLite copy, then remove that plaintext. Never overwrite live Recorder data or
start cloned Matter/Thread controllers as a test.

Missing/stale-stream alerts, unattended off-host restore checks and the guarded
storage-recovery watchdog are not yet installed. A clean backup does not resolve
the earlier USB/storage reliability problem or repair older quarantined history.

## Full HA/controller backup proposal (not yet automated)

The deployed isolated source retains extra legacy `ix-state-backup.timer` entries
for HA, Matter and Thread which the checkout's older `backups.nix` lacks. Preserve
that coverage when deploying; do not activate the checkout wholesale. Those legacy
archives are **not evidence of consistent live SQLite/controller snapshots**.
Coordinated off-host preservation performed during recovery is separate from the
measurement-only hourly job above.

### Recommended design

1. Use HA's native **Backup integration** for `/var/lib/hass` on this NixOS/Core
   installation, including `.storage` (original owner/users, entities, integration
   credentials, dashboards/energy preferences), scenes and Recorder database.
   HA2026.9 explicitly supports local Core/Container backups. Its Recorder backup
   hooks lock database writes during capture and unlock afterward: do not simply
   tar a live SQLite database/WAL with `--ignore-failed-read`.
2. Separately protect `/var/lib/matter-server` and `/var/lib/thread`, including the
   commissioned fabric, CHIP storage and original OTBR settings. They are outside
   the HA configuration directory and are **not implicitly included** in an HA
   backup. Do not sync the live directories between running controllers. Use a
   deliberately coordinated maintenance snapshot for these external services;
   any required Matter/OTBR stop/restart needs explicit scheduling/approval.
3. Encrypt before leaving ix. Reuse the existing age recipient arrangement
   (personal recovery key plus ix host key) for the complete snapshot bundle, or
   native HA backup encryption with its recovery kit stored separately. Keep a
   recovery key somewhere other than ix; never store only the key on the failing
   disk and never print it into logs.
4. Store immutable/versioned encrypted files **off-device**, preferably on Moby,
   with an additional independent copy. Confirm destination ownership, capacity
   and access first. Existing Syncthing transport can be reused only after its
   receiver is accepted/unpaused and successful remote delivery is verified.
   Synchronization alone is not versioned backup; retention must protect older
   copies from accidental deletion.
5. Suggested policy: nightly HA backup, external Matter/Thread snapshot after
   pairing or network changes, retain7 daily/4 weekly/3 monthly generations.
   Record checksums, HA/Matter/OTBR versions and the matching Nix generation.
   Keep configuration in Git too, but Git cannot replace application data.
6. Verify decryption, archive completeness, JSON identity/schema checks and
   SQLite integrity on an extracted disposable copy **off ix**. A successful
   copy is not a successful restore test. Never start a cloned Matter/Thread
   controller alongside the original during testing.
7. Alert on failed creation, stalled transfer, missing remote copies and stale
   last-success time. Refuse capture if the current full-kernel storage fault
   gate reports new disk/USB/power errors; do not add automatic repair/retry loops.

### Approval needed for the comprehensive proposal

Confirm retention and a coordinated external-state snapshot window before adding
automated full HA/Matter/Thread captures. The active measurement job does not stop
those services, replace identities, restore quarantined history, or substitute for
that comprehensive backup policy.
