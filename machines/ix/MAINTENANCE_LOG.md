# Raspberry Pi 4 deployment and troubleshooting log

This log records decisions, failed attempts, verified results, and recovery paths.
It is intentionally separate from private runtime evidence: no mail contents,
passwords, private keys, OAuth tokens, or application databases belong in Git.

## Scope and operating rules

- Target: Raspberry Pi 4 Model B revision 1.4, 8 GB RAM, hostname `raspi4`.
- Working storage: WD My Passport 4 TB; serial `WD-WX41DA8PFDHX`.
- microSD: 7.4 GiB, retaining Raspberry Pi OS as a recovery installation.
- Use an independent, headless Home Manager profile, not the full moby profile.
- Preserve unrelated changes in this repository and preserve all source data.
- No reformatting during deployment. Identify disks by serial/partition identity,
  never by assuming that `/dev/sda` means the same disk on two machines.
- Build the deployable system and boot artifacts on **moby before deployment**.
- First finish and reboot-test the permanent NixOS foundation. Only then perform
  copy-first functionality/data migrations; do not delete the moby originals.
- Operator authorized unattended implementation and, **only once the Pi and
  required migrations are verified**, shutting down moby. A blocker means moby
  stays on. Save final documentation on the Pi before any shutdown.

## 2026-09-27–28 — Hardware and USB boot investigation

### Samsung NVMe / Realtek enclosure: separate unresolved problem

The Samsung NVMe in the Plugable/Realtek RTL9210 enclosure exposed no usable
capacity: macOS saw the USB bridge but no disk media; Linux reported a 0-byte
block device. READ CAPACITY(10), READ CAPACITY(16), and NVMe identification through
SMART passthrough failed with unsupported/invalid SCSI commands. Reseating did
not resolve it. No filesystem was created and no data was written to this SSD.

This is distinct from the WD HDD issue. The WD consistently exposed its full
4000752599040-byte capacity and was readable from Raspberry Pi OS.

### WD HDD: existing NixOS image was present

A read-only audit (ext4 mounted with `ro,noload`) found:

- GPT, 128 MiB FAT firmware partition labeled `RPI4_BOOT`.
- Large ext4 root partition labeled `NIXOS_RPI4`.
- Firmware, `u-boot.bin`, extlinux configuration, Linux kernel, matching DTBs,
  initramfs, and the NixOS system closure.
- Clean filesystem and no evidence that normal NixOS first-boot activation had
  completed. The issue was not simply a different IP address.

The installation had been produced by a separate setup lane; diagnostics did
not repeat its installer or reformat the HDD. Moby's internal disks were never
used as substitutes for the Pi's `/dev/sda`.

### Firmware-level USB failure

The original boot order was `BOOT_ORDER=0xf14`: USB first, SD fallback, repeat.
The EEPROM already supported USB boot. HDD-only boot and a USB 2 test did not
produce verified SSH; putting the recovery SD back restored Raspberry Pi OS.

The first monitor photo showed firmware errors before U-Boot/Linux:

```text
LUN 0 timeout 3000 ms
MSD error ... error 2
xHC-CMD err: 6
```

`vcgencmd get_throttled` returned `0x0` in repeated Raspberry Pi OS checks. That
alone does not rule out USB startup-current or bridge compatibility problems.

### EEPROM timing experiments

All EEPROM experiments preserved the firmware version (2026-05-17,
`224877da90f82a72dbcc9db10bcf059259f54680`), backed up prior settings, and verified
candidate configuration, firmware payload, and staged image checksum.

1. Added `USB_MSD_STARTUP_DELAY=10000`. Verified applied; insufficient to fix boot.
2. Added `USB_MSD_LUN_TIMEOUT=10000` and `USB_MSD_DISCOVER_TIMEOUT=60000`.
   Verified applied later through Raspberry Pi OS. A subsequent boot reached
   U-Boot, but not Linux. This was progress, not proof of a complete fix.

The updater changes the final eight timestamp bytes of its staged image. An
initial full-file comparison mismatch was investigated and resolved: the
remaining payload and intended configuration matched. It was not ignored.

Authoritative setting documentation was retrieved from Raspberry Pi's
`documentation` repository. The LUN timeout governs advancing between logical
units; it is not a general cure for every USB command timeout.

### Second-stage failure: U-Boot

A newer photo showed:

```text
Disk usb_mass_storage.lun0 not ready
EFI boot manager: Cannot load any image
DHCP client bound to address 192.168.1.162
TFTP error: -1 (Request timeout)
```

The network address was acquired by **U-Boot**, not Linux. Therefore a pingable
address without SSH did not establish successful NixOS boot. The TFTP messages
were fallback network boot, not a router problem requiring reconfiguration.

Using an attached keyboard, the operator interrupted U-Boot and tried:

```text
usb reset
usb storage
part list usb 0
```

The reset still reported LUN 0 not ready, and `usb storage` found no usable
storage. A temporary RAM-only `setenv usb_pgood_delay 5000` followed by another
reset also failed. No `saveenv` or disk-write command was used.

Conclusion: stop repeating timeout experiments. Linux under Raspberry Pi OS
could access the HDD, whereas the attempted bootloader path could not. This
does not establish that the HDD itself is defective.

A previous network-monitor subagent failed before producing monitoring results
because of a tool/runtime import error. It was closed; no fallback runner was
silently substituted. Later diagnostic checks were bounded parent-session
checks. No monitoring subagent remains active.

## 2026-09-28 — Successful SD direct-Linux / HDD-root test

### Reversible preparation

The operator booted Raspberry Pi OS with the HDD unplugged, then reattached the
HDD after SSH returned. Model, serial, capacity, labels, and unmounted state were
rechecked. The SD FAT partition had approximately 430 MiB free.

Backed up the entire pretest SD boot partition and added only:

```text
tryboot.txt
nixos-sd-test/Image
nixos-sd-test/initrd
nixos-sd-test/bcm2711-rpi-4-b.dtb
nixos-sd-test/armstub8-gic.bin
nixos-sd-test/cmdline.txt
```

Kernel/initrd/DTB hashes matched both the installed HDD files and the original
Nix store build on moby. Existing Raspberry Pi OS `config.txt` and `cmdline.txt`
were left unchanged. The test command line preserved the installed NixOS init
path and added `panic=30`.

A fresh NixOS SSH host key was generated directly on the HDD, mode 0600. No
existing key was replaced, and no private key was copied to moby or placed on
the FAT partition. Its public key was obtained over the already-trusted
Raspberry Pi OS SSH connection and pinned before first NixOS boot.

Public host fingerprint:

```text
SHA256:Tmtnt6phRTJ/19ctgTjxf0uY0wp00hoNjhH0Ys42qOs
```

Changed boot order to **`BOOT_ORDER=0xf41` (SD first, USB fallback)** and verified
it in a separate normal reboot. Then issued `sudo reboot '0 tryboot'`.

### Verified result

Around 05:00–05:03 UTC, authenticated SSH reached `raspi4`:

- NixOS 26.11, Linux 6.18.52.
- Firmware device-tree values: `boot-mode=1`, `partition=1`, `tryboot=1`.
- SD firmware loaded Linux directly; **U-Boot was bypassed**.
- `/`, `/nix`, `/var`, and `/home` were on the verified WD HDD's ext4 partition.
- Both SD partitions and the HDD firmware partition were unmounted after boot.
- Approximately 3.4 TiB free, 7.6 GiB RAM visible, 1.9 GiB zram.
- `systemctl is-system-running` returned `running`; zero failed units.
- The expected SSH host fingerprint matched exactly.

The initial wall clock was stale until NTP corrected it. March-dated entries
near the beginning of this boot's journal are not evidence of an older boot.

### Warnings to address in the permanent profile

- The generic image's fstrim timer ran once. The HDD rejected a WRITE SAME(16) /
  DISCARD request (illegal request, unsupported opcode `0x93`), although fstrim
  reported success. No read/write I/O failure was observed. Disable unnecessary
  TRIM for this HDD configuration rather than treating this as media failure.
- Bluetooth initialization timed out. Do not claim Bluetooth support is working.
- Generic image modules included ZFS and staging drivers that are unnecessary
  for the headless ext4 bootstrap; tailor the permanent hardware profile.

### Recovery and private evidence

At this checkpoint, the test remains one-shot: an ordinary reboot starts
Raspberry Pi OS. The installed bootstrap generation still uses generic extlinux;
its rebuilds do **not** maintain the manually staged SD boot files. This must be
fixed before declaring the persistent installation complete.

The tested closure is protected by `/nix/var/nix/gcroots/raspi-sd-direct-test`.

Pretest backup on the **Raspberry Pi OS SD root**, not the NixOS HDD root:

```text
/var/tmp/raspi-sd-direct.wy2rpq5_
```

Private moby evidence and backup copy:

```text
~/.local/state/raspi4-setup/sd-direct-20260928/
  RESULT.md
  verified-manifest.json
  stage.log
  sd-first-verification.txt
  tryboot-ssh-result.txt
  nixos-boot-verification.txt
  trim-and-recovery-check.txt
  pi-pretest-backup.tar.zst
```

Backup archive SHA-256:
`f2a772ca45351c97940018bb48e6be98ccac91d4e3e3ab821e29574669ae84ab`.

The isolated SSH host pin is in `nixos-known-hosts` in that private directory;
existing Raspberry Pi OS SSH trust was preserved rather than replaced.

## 2026-09-28 — Permanent installation: in progress

Operator confirmed:

1. Make NixOS the default and make future kernel updates maintain SD boot files.
2. Put the configuration and this troubleshooting log in the existing repository.
3. Finish and verify the NixOS foundation before functionality migrations.
4. Build on moby before deploying; proceed without further routine input.
5. Shut down moby only after the Pi and required copies/services are verified,
   with the final log saved on the Pi first.

Planned foundation gate:

- Independent `nixosConfigurations.ix`, explicit hardware identities, and
  minimal independent Home Manager integration.
- Direct-SD boot update mechanism, preservation of Raspberry Pi OS recovery,
  safe handling of limited FAT space, and documented NixOS rollback.
- Tests and build on moby; transfer only verified build artifacts to the Pi.
- Real normal reboot into NixOS (not merely one-shot), update/rollback checks,
  correct HDD root, SSH identity, networking, and clean required service status.
- No mailbox, application-state, credential, or live database migration before
  this gate passes. No source deletions during the later copy-first phase.

Subsequent entries will distinguish changes made, tests passed, and blockers;
planned work is not evidence of completion.

## 2026-09-28 — Permanent foundation passed

### Implementation and build on moby

Added `nixosConfigurations.ix`, `machines/ix/{default,hardware,direct-boot}.nix`,
and the independent `homes/ix/home.nix`. No full desktop/personal Home Manager
module was imported. The host uses Ethernet DHCP, key-only SSH, zram, bounded
journaling, and the existing HDD/SD partition UUIDs. Disabled HDD fstrim and the
previously failing Bluetooth UART initialization. No partition was reformatted.

`bootloader.py` implements the external NixOS bootloader hook. It consumes the
bootspec and matching kernel, initramfs, DTB, and ARM stub; verifies the physical
target; stages checksum-verified content-addressed objects; checks capacity;
and promotes the default configuration with atomic rename and fsync. It retains
two generations, additionally protects an older running generation when needed,
and maintains Nix GC roots. FAT is not a fully power-loss-transactional filesystem;
the preserved Pi OS configuration and full boot backup remain important.

An initial deprecated journald setting failed evaluation and was corrected to
`services.journald.settings.Journal.SystemMaxUse`. ARM builds were verified on
moby's active QEMU/binfmt setup. The initial 13 tests passed; after the recovery
correction described below, **18 tests passed**. Both system and FAT boot image
were built on moby before transfer. Image construction included `fsck.fat -n`;
SHA-256 checks passed on both moby and the Pi. The FAT image is an artifact, **not
an instruction to overwrite the existing SD or HDD**.

Initial foundation A:

```text
/nix/store/5dn46n2cgdgnrqv2f73k01vps98zwmir-nixos-system-raspi4-26.11.20260917.e554fab
```

Corrected, current foundation B:

```text
/nix/store/bn7c3pia04vl6dlz6705znh7ynjrks1v-nixos-system-raspi4-26.11.20260917.e554fab
/nix/store/9ga5ayc8wc6p8l0hv043mahcnx2pr3q7-raspi4-boot-image
```

### Discovered and corrected: mainline-kernel tryboot limitation

For the first new-generation trial, normal boot was temporarily restored to
Pi OS and `tryboot.txt` pointed at A. Issuing `reboot '0 tryboot'` **from the
mainline NixOS kernel** instead performed a normal Pi OS boot. No new NixOS
journal boot appeared. The elapsed boot timing and firmware log agreed with
normal boot, not a failed candidate followed by a panic/reboot.

Source inspection confirmed the distinction: Raspberry Pi's vendor firmware
driver handles the `tryboot` reboot argument and sets mailbox reboot flags;
the upstream watchdog restart handler does not. NixOS exposed `/dev/vchiq`,
but not the vendor `/dev/vcio` mailbox interface. Therefore neither a bare
`reboot '0 tryboot'` nor an untested mailbox workaround is an acceptable NixOS
recovery procedure. No speculative MMIO writes or kernel patches were used.

Initiating the trial **from Raspberry Pi OS** successfully booted A, with the
expected HDD root, SD `/boot`, SSH identity, successful Home Manager activation,
and zero failed units. B retained the exact same kernel, initramfs, and kernel
parameters; it corrected the recovery tooling.

The portable `raspi4-recovery` helper now saves the NixOS return configuration,
selects the preserved Pi OS `config.txt`, and performs an ordinary reboot.
**Recovery stays selected until explicitly restored.** Standalone Python tools
and policy are saved on the FAT partition, so Pi OS can restore or select a
retained NixOS generation without a mounted Nix store or a running moby.

### Live boot/update/recovery/rollback verification

Each listed successful boot had a changed boot ID, the expected separately
pinned SSH identity, correct root filesystem, `systemctl is-system-running =
running`, and zero failed units:

| Check | Boot ID |
| --- | --- |
| A trial from Pi OS | `f3d977ee-025c-4297-84ef-a00af8f595f7` |
| B normal NixOS boot | `70cc9a55-c93f-4fba-97d5-1b82e96081ab` |
| B → Pi OS recovery | `31f138f1-860f-4e9f-910f-78b3862aae42` |
| Pi OS → B restored normal boot | `ea499a61-2b80-4485-8567-fc07cb05daea` |
| B → A normal rollback boot | `e943e98d-70a2-4837-a85d-2cfd789ac942` |
| A → B reapplication and normal boot | `77baacb6-2641-402b-bc86-2229353720a8` |

Normal NixOS boots reported firmware `boot-mode=1`, `partition=1`, `tryboot=0`.
The WD supplied `/`; the SD FAT partition supplied `/boot`; the Pi OS ext4 root
and old HDD firmware partition were unmounted. About 253 MiB remained free on
the 505 MiB usable FAT filesystem, including the original one-shot test assets.

Rollback initially hit nixos-rebuild's configuration re-execution step before
changing any profile: there was not yet a local `/etc/nixos` checkout. The tested
offline command is `sudo nixos-rebuild boot --rollback --no-reexec`. Reapplication
used `sudo nixos-rebuild boot --no-reexec --store-path <prebuilt-system>`.
An SSH connection closing during reboot can return 255; the checker was corrected
to require a new authenticated boot ID instead of assuming that this transport
exit code proves failure or success.

A is retained as a tested rollback generation, but its old `raspi4-recovery`
wrapper has the now-known tryboot defect. The final default is B, with the fixed
helper. Use B's helper by absolute store path if recovery is needed while A runs.

### Foundation status and residual notes

At the 06:25 UTC audit, the Pi was running B normally. Home Manager reported
`Result=success`, `ExecMainStatus=0`; 7.6 GiB RAM and 1.9 GiB zram were visible.
The effective SSH configuration disables root, password, and keyboard-interactive
login. fstrim is absent. The WD enclosure's unsupported diagnostic-page messages
and duplicate D-Bus service-name warnings remain nonfatal observations; no
normal disk read/write failure or failed unit was observed.

Tailscale is installed but reports **NeedsLogin**; no identity was cloned or
enrollment fabricated. LAN SSH is verified. Application/mail migration has not
yet occurred. The foundation gate is now passed; copy-first migration may begin.
Moby remains on, and the final shutdown gate is **not yet passed**.

Detailed private evidence remains under
`~/.local/state/raspi4-setup/sd-direct-20260928/`, particularly `foundation-v2-*`,
`foundation-normal-boot.txt`, `foundation-recovery-{boot,return}.txt`,
`foundation-rollback-boot.txt`, `foundation-reapply-boot.txt`, and
`foundation-final-audit.txt`. See [README.md](README.md) for operating commands.

## Application/data migration and final handoff — 2026-09-28

This section supersedes the earlier foundation-only status above. The operator
subsequently requested a **fresh minimal Home Assistant**, not state migration,
and explicitly removed Mac synchronization from the completion/shutdown gate.
The independent headless profile remains separate from `homeModules.amunoz`.

### Copy-first data and source preservation

An immutable checkpoint was created through the existing authorized root terminal:
`zroot/local/home@raspi4-copy-first-20260928T063821Z`. Mail synchronization was idle
at capture. The copy order was `.mail`, `.cache/mirror-mail`, `.pi/agent/sessions`,
then `Documents`; there was no source deletion, formatting, or `rsync --delete`.
Each dataset was checksum-compared before completion was claimed. The live mu
index was excluded and rebuilt natively instead.

Initial mail data comprised 38,773 regular files / 10,218,648,796 bytes. Documents
comprised 94,680 regular files / 68,558,281,912 bytes, plus directories/symlinks.
The unprivileged copy exited 23 because fifteen legacy-owned Documents files
were unreadable. A root sender with the same strictly pinned, unprivileged SSH
transport copied the missing 22,871,755 bytes and checksum-verified the entire
Documents dataset. Original file ownership and permissions were not changed.
The failed transient unit was reset only after this successful recovery.

Final reconciliation used `zroot/local/home@raspi4-final-20260928T083445Z`.
Change-time comparison found no Documents entries changed since before the first
checkpoint. The current session transcript was refreshed; all 695 session files
(total 534,922,808 bytes) were checksum-verified. Both snapshots and all original
source data remain on moby. Session copies are not concurrent writers; future
cross-machine synchronization remains paused for deliberate reconciliation.

### Independent applications and credentials

Installed versions verified on native ARM: Emacs 31.1, mu 1.14.3, isync 1.5.1,
msmtp 1.8.32, Git 2.55.0, Git LFS 3.7.1, Node 24.20.0, npm 11.19.0, Pi 0.85.1,
Syncthing 2.1.3, and Home Assistant 2026.9.2. The editor is a small standalone
terminal/mu4e/Org configuration, not the desktop package tree.

The two scoped mail passwords were transferred directly from the unlocked vault
into private Pi runtime files. Purdue OAuth state was decrypted only in process
memory, sent through pinned SSH, and encrypted with a **new Pi-only GPG key**.
The unattended key relies on private filesystem permissions; moby's private GPG
key was not copied. Tokens/passwords were not printed or put in Git/Nix inputs.

All three accounts passed TLS IMAP read-only and SMTP authentication tests; no
SMTP test message was sent. Purdue's refresh token was exercised on the Pi.
Testing the actual mail client then exposed that plain `pkgs.isync` lacks the
Microsoft XOAUTH2 plugin. The profile now explicitly uses
`isync.override { withCyrusSaslXoauth2 = true; }`, matching the source setup.
The corrected six-channel pull succeeded, then the native index completed.

Only after the complete verified seed, normal source mail directions were
previewed with `mbsync --dry-run`: one far-side append, no far-side deletions,
and thirteen near-side removals. The matching policies were then activated.
The actual run completed, and the subsequent post-reboot run reported zero
changes across six channels / 36 mailboxes. The local index contained **38,988
messages** at cutover. Emacs starts mu4e only after the index-success marker;
its five-minute update timer and live server were verified after reboot.
Normal Trash moves do not set the immediate-deletion flag, and permanent delete
is deliberately disabled. Mailbox removal remains disabled.

Pi's single provider credential was privately copied once, mode 0600, **outside**
the session share. A direct fixed-response provider API check with the configured
`openai-codex/gpt-6-astra` model returned `OK`, with zero tools and no delegated
work. CLI model discovery also recognizes that model. Optional extensions,
including the incompatible earlier subagent stack and the moby Hindsight client,
were not imported. Hindsight's live database remains untouched on moby.

A shell-only npm prefix setting was insufficient for non-login SSH commands.
The simpler reliable configuration is Home Manager's `programs.npm` module with
prefix `~/.local`. An offline local-package global install, execution, and
uninstall passed without writing into the Nix store or running package scripts.
The repository's public HTTPS origin was checked from Pi; private signing/SSH
keys were not copied. Native Pi flake evaluation matched the moby-built cutover
derivation before subsequent documentation-only updates.

### Fresh Home Assistant; synchronization deferred

An early consistent HA export was taken with a brief stop/restart of moby's
controller; source HTTP 200 was verified afterward. The operator then explicitly
changed scope to **fresh setup**. The verified, unused Pi import and its Pi-side
archive were removed before enabling the new controller. Moby's original state
was not removed. Migration-only HA checker/condition/helper code was deleted,
leaving the ordinary NixOS service with frontend and onboarding weather support,
without Roborock, broad `default_config`, discovery, Bluetooth, or recorder.

HA 2026.9 initially treats the YAML listen address as a pending HTTP migration.
Merely seeing a loopback socket once is insufficient: the pending setting can
fall back. With the fresh Pi service stopped, its own newly generated loopback
candidate was accepted into `data.stable`, clearing `data.pending`. No source
state was used. The onboarding page returned HTTP 200 and the accepted
`127.0.0.1:8123` listener persisted across reboot. There were zero non-system
users, and no imported Roborock configuration. Owner onboarding is intentionally
left to the user.

Syncthing has a fresh device identity:
`[private device ID — sent by email]`.
Its GUI is loopback-only and password-protected; public/local discovery and
public relays are disabled. The transfer port is allowed only on `tailscale0`.
LAN connection attempts to 8384, 22000, and 8123 did not succeed. Documents and
Pi sessions remain paused/receive-only until peer reconciliation. Tailscale
still requires legitimate enrollment; no identity cloning or privacy downgrade
was used. Per the updated instruction, Mac synchronization is **not a blocker**.

### Final build, real boot, and evidence

The final system and its FAT artifact were built on moby before transfer:

- `/nix/store/zvyxcisp28x76jqgrqk999vb87f8i85n-nixos-system-raspi4-26.11.20260917.e554fab`
- `/nix/store/b5s58mg3shganjhvmrvkqichfcfgfb4j-raspi4-boot-image`

Kernel, initrd, and kernel parameters match the previously proven foundation.
Image checksum verification passed on both machines. A real normal reboot
produced boot ID `7a550192-26b8-4ab8-a818-eff30338a200`, with matching current and
booted system paths, WD root, SD `/boot`, system state `running`, and no failed
system units. The earlier full application boot also passed with boot ID
`07fd8a06-4af3-4b64-b18c-70bc6478c545`.

Private migration evidence is in
`~/.local/state/raspi4-setup/migration-20260928/` on moby; selected non-secret
receipts and final source/recovery material are copied to
`~/.local/state/raspi4-deployment/` on Pi. The final user-facing summary is
[DEBRIEF.md](DEBRIEF.md). Shutdown is the last step after final documentation
verification; its request/observation is recorded separately rather than
claiming a scheduled request is already an observed power-off.

## Final ix identity and shared workspace — 2026-09-28

The later operator requests supersede the initial minimal-editor/Tailscale
pending-enrollment state above:

- Hostname, flake entry, directories and operator commands are **ix**.
  Branch: `ix-migration`. Working changes remain uncommitted, with the full
  overlay and Git bundle preserved privately on ix; unrelated work retained.
- Tailscale enrollment was manually approved: `Running`, healthy, DNS name
  `ix.tail5e510f.ts.net`. Syncthing peer addresses use tailnet DNS names.
  Discovery/relays remain disabled and both folders paused/receive-only.
- The private Syncthing ID was removed from repository documentation and sent
  to the owner by email; receipt was verified read-only in the actual Inbox.
- ix uses the shared Emacs configuration and shared Fish module with Pure,
  autopair, fishbang, fish-you-should-use, sponge and async-prompt. Native ARM
  dependencies come from Nix; portable Straight sources exclude x86 binaries.
  Ghostel 0.44.0's ARM module executed a real Fish command successfully.
- After reboot, Emacs reported hostname ix, no init error, Meow/Vertico enabled,
  Pi dashboard configured, native PDF backend working, and local gptel/Pi
  authentication available without printing credentials. Google Calendar
  integration/agenda entry was removed; personal data and credentials retained.
- The complete mail pipeline passed before reboot: Purdue/Broad/Broad spam
  appended 59/25/7 messages respectively, with zero errors or deferred messages.
  SQLite import receipts were transferred consistently and integrity-checked.
  **The operator explicitly waived further periodic-mail-timer investigation**
  after the last post-reboot probe found it inactive; it was left untouched.

Final built, activated and genuinely booted system:

- `/nix/store/b0xyxb3612x462xnijm4lssdxqzhp4kq-nixos-system-ix-26.11.20260917.e554fab`
- FAT artifact: `/nix/store/3mhav6whyphkaaygh1skjjmbd3cgq668-ix-boot-image`
- Authenticated boot ID: `5b4f7c4d-6987-4489-933d-ff8223355d70`

Both artifacts were built on moby first, copied with pinned SSH and checksum-
checked. Current and booted system paths match; hostname is ix, WD ext4 root
and SD FAT `/boot` are correct, and there are no failed system/user units.
HA onboarding returned HTTP 200 after startup; accepted HTTP settings remain
loopback-only with no pending migration. Emacs, HA, Syncthing and Tailscale are
active. The ix test suite passed 26 tests; mirror-mail passed 19 tests.

The broad all-grammars build encountered an unrelated CUDA source hash mismatch;
only needed language grammars were selected rather than accepting an unverified
hash. The native PDF helper was exposed on PATH through a Nix wrapper. Cold
application startup takes longer than SSH/systemd readiness: test the actual
Emacs socket and HA endpoint, not just `is-system-running`.

Legacy on-disk boot/credential/lock identifiers remain unchanged. Old source
containing historical private documentation was moved out of the checkout into
private recovery storage. A locally Git-ignored legacy home link points to the
**original minimal init**, not the new loader that needs additional packages.
This preserves old profiles' out-of-store source dependencies without changing
the current ix loader. No additional recovery reboot was needed for that link
correction; the earlier real recovery/rollback evidence remains preserved.

Final source bundle, working-tree archive, hashes, live checkout and private
conversation checkpoint are retained on ix. The shutdown receipt distinguishes
an accepted graceful shutdown request from any later network observation; it
does not claim physical power-off solely because SSH becomes unavailable.
Mac sync, Hindsight relocation and ZFS conversion remain follow-up work in the
[ix-only roadmap](ROADMAP.md), not shutdown gates.

## Purdue junk routing correction

The archive importer used to flatten Purdue's `Junk Email` into `INBOX.Purdue`.
It now routes source-Junk members directly to MXroute's native `Junk`, and uses
UID MOVE to correct matching existing archive copies. Exact Message-ID/archive
keys are used, not sender/subject guesses or stale spam headers (which were
also present on legitimate forwarded mail). Source-folder classification wins
across duplicates. Pending deletions, Trash, and other user-filed folders are
left alone; receipts prevent deleted imports from being recreated. Purdue's
original IMAP account remains pull-only.

The updated `ix-mail-sync` package was built natively from this checkout without
a system switch/reboot. A scoped `~/.local/bin/ix-mail-sync` launcher selects the
GC-rooted package under `~/.local/state/purdue-junk-fix/package` while the managed
package is unchanged, then automatically defers to the managed package after
its next deployment. Remove that launcher after a normal deployment includes
this change. The private state directory holds the original script, preexisting
worktree diff, consistent SQLite receipt backup, exact move preview, and sync
log. No credentials or message headers were added to Git. The live Emacs process
resolves the new launcher; unrelated editor changes in ix's checkout were kept.

Verification: seven existing copies (six distinct message IDs) were moved to
Junk, with zero Purdue-junk keys remaining in the archive on either MXroute or
ix. A second Purdue import appended/moved zero messages, with zero errors or
deferrals. Previously removed imports were not resurrected. The ordinary full
sync finished its mbsync and Purdue stages; its unrelated multi-GB Broad scan
was cleanly interrupted rather than delaying this repair further. A subsequent
locked, Purdue-only verification and two-mailbox mbsync completed successfully,
and the live mu4e index was refreshed. All 39 email tests passed locally and on
ix; 35 ix policy/boot tests passed locally. No full Broad import completion or
change to automatic sync scheduling is claimed.
