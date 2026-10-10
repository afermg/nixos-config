# Home Assistant backup proposal (not yet enabled)

The repository's `ix-state-backup.timer` policy does not include Home Assistant,
Matter Server or Thread data. The previously deployed isolated source has additional
legacy archive entries for those directories; those are **not evidence of a
consistent live SQLite/controller snapshot or a successful off-device restore**.
Its `ix-backups` Syncthing folder is documented as paused/send-only pending remote
acceptance. No reliable off-device Home Assistant backup has been demonstrated. A second archive on ix's same HDD would not
protect against that disk/USB path failing.

## Recommended design

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

## Approval needed before enabling

Confirm Moby (or another host) as destination, retention and the coordinated
external-state snapshot window. No new application-data backup or background
backup job has been enabled or manually started by this work; existing timer
activity has not been audited as part of this proposal. Existing archives, current data,
credentials, accounts and controller identities are untouched.
