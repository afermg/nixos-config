# ix: headless NixOS, direct SD boot, HDD root

See [DEBRIEF.md](DEBRIEF.md) for the final application/data handoff and deferred
items, and [MAINTENANCE_LOG.md](MAINTENANCE_LOG.md) for the deployment history and troubleshooting.
The server hostname and flake entry are **ix**. Its independent Home Manager
profile in `homes/ix/home.nix` reuses the personal Emacs and Fish configuration
without importing the desktop home. Future work is scoped in [ROADMAP.md](ROADMAP.md).

## Storage and access

- Raspberry Pi 4B revision 1.4, 8 GB; Ethernet MAC `dc:a6:32:c2:0b:8b`.
- Normal access: `ix.tail5e510f.ts.net` through the approved Tailscale node.
  Ethernet uses DHCP; discover the current LAN lease only for recovery.
- SD boot: `/dev/disk/by-partuuid/5e49d9dc-01`, mounted at `/boot`.
- Existing Pi OS recovery root: `/dev/disk/by-partuuid/5e49d9dc-02`; normally unmounted.
- NixOS root: ext4 on `/dev/disk/by-partuuid/82f0384a-132d-483f-8888-98c201d166d7`.
  ZFS is an evaluation/migration roadmap item, not enabled on ix today.
- WD HDD: serial `WD-WX41DA8PFDHX`, 4000752599040 bytes. Never infer its identity
  from `/dev/sda` on another host.
- Firmware boot order is SD first, `BOOT_ORDER=0xf41`. SD firmware loads Linux
  directly, not U-Boot. The old HDD firmware partition is unused.
- Key-only SSH as `amunoz`; root SSH/password authentication disabled. This
  administrative user has passwordless sudo and is a trusted Nix user on the Pi.
- NixOS Ed25519 fingerprint: `SHA256:Tmtnt6phRTJ/19ctgTjxf0uY0wp00hoNjhH0Ys42qOs`.
  Keep its host pin separate from the existing Pi OS identity; never disable
  checking or overwrite Pi OS trust to work around an expected OS change.
- Tailscale enrollment was manually approved; its verified state is `Running`.

Save the public pin below as `~/.ssh/known_hosts_ix` on your client and add:

```sshconfig
Host ix
  HostName ix.tail5e510f.ts.net
  User amunoz
  HostKeyAlias ix
  UserKnownHostsFile ~/.ssh/known_hosts_ix
  GlobalKnownHostsFile /dev/null
  StrictHostKeyChecking yes
  HostKeyAlgorithms ssh-ed25519
  UpdateHostKeys no
  ForwardAgent no
```

Then use `ssh ix`. This works with Bash or Fish and needs no fixed IP.

The public pin entry is:

```text
ix ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKY0holJSH6l/MeBPRWgzITfAVwT7dJESRBTP0pHjQA7
```

## Build and deploy (no disk image flashing)

Build on moby first. Its aarch64 binfmt/Nix build support must be active.
Keep the existing lockfile and unrelated working-tree changes intact.

```sh
python3 -m unittest discover -s machines/ix/tests -v
nix build --no-write-lock-file --no-link --json --max-jobs 2 --cores 2 \
  .#nixosConfigurations.ix.config.system.build.toplevel \
  .#nixosConfigurations.ix.config.system.build.ixBootImage
```

Record the resulting store paths. The image output contains
`ix-boot.fat.img`, `manifest.json`, and `SHA256SUMS`; validate with
`sha256sum -c /nix/store/...-ix-boot-image/SHA256SUMS`.
**This 256 MiB FAT filesystem is a build artifact, not a whole-disk installer.
Do not dd it over the SD, HDD, or their existing partitions.**

Copy the two verified outputs using the pinned SSH options:

```sh
nix copy --no-check-sigs --to ssh://ix "$system" "$image"
```

`--no-check-sigs` is for these locally built, authenticated outputs; it is not
permission to import arbitrary untrusted store data. The Pi administrator is
already explicitly a trusted Nix user.

On the Pi, optionally activate/test userspace first, then select the prebuilt
system for the next normal boot:

```sh
sudo "$system/bin/switch-to-configuration" test
sudo nixos-rebuild boot --no-reexec --store-path "$system"
sudo systemctl reboot
```

The external hook installs matching kernel/initrd/DTB/ARM-stub/cmdline objects,
verifies target hardware and capacity, and updates the SD default. It preserves
Pi OS boot files and keeps two NixOS generations plus an older booted generation
if required. Managed generations have explicit Nix GC roots. Do not manually
remove those roots, `/boot/nixos`, or the active system closure.

Verify a changed boot ID, `/run/{current,booted}-system`, `/` on the WD, `/boot`
on SD, SSH identity, successful Home Manager activation, and no failed units.
An SSH exit 255 during reboot alone is neither proof of failure nor of success.

The declarative source can also build natively on the Pi when necessary; it
must not require moby at runtime. Integrated Home Manager is managed through
the NixOS configuration, not the desktop user's standalone profile.

## Rollback

From a working NixOS generation:

```sh
sudo nixos-rebuild boot --rollback --no-reexec
sudo systemctl reboot
```

`--no-reexec` avoids evaluating an absent local configuration merely to select
an already-built generation. This path was tested with real reboots. To return
to another prebuilt generation, use the `--store-path` deployment command above.

The first foundation A is bootable but has the obsolete tryboot-based recovery
wrapper. While running A, invoke the fixed B helper explicitly if needed:

```sh
sudo /nix/store/bn7c3pia04vl6dlz6705znh7ynjrks1v-nixos-system-raspi4-26.11.20260917.e554fab/sw/bin/raspi4-recovery
```

## Raspberry Pi OS recovery (tested round trip)

From the current NixOS generation:

```sh
sudo ix-recovery
```

This saves the NixOS return configuration, selects the original Pi OS config,
and reboots normally. **Pi OS remains selected until explicitly restored.**
Use the original Pi OS SSH identity and its current LAN DHCP address when
connecting to it; the NixOS Tailscale name is not a Pi OS recovery connection.

The `raspi4-recovery` directory, bootspec identifier, GC-root prefix, and lock
names are stable **on-disk compatibility identifiers**, not the current hostname.
They are deliberately retained so existing rollback/recovery tools remain valid.

From Pi OS:

```sh
sudo python3 /boot/firmware/raspi4-recovery/recovery.py restore --reboot
```

To select the previous retained NixOS boot configuration instead:

```sh
sudo python3 /boot/firmware/raspi4-recovery/recovery.py restore --previous --reboot
```

The restore helper validates hardware identities and boot-object checksums;
it does not need a mounted Nix store, moby, or Internet access. Selecting an
older boot configuration does not itself edit the HDD's Nix profile history.

**Do not use `reboot '0 tryboot'` as the NixOS recovery command.** That argument
works with the Pi OS vendor kernel, but was ignored by this generic NixOS kernel.
The tested recovery helper deliberately avoids that dependency.

If NixOS cannot reach SSH at all, shut down/disconnect power safely and use
another machine to restore the SD FAT `config.txt` from
`raspi4-recovery/config.txt`, leaving `cmdline.txt` and original Pi OS assets
intact. Reinsert the SD and boot Pi OS. Never reformat the card as a first step.
The full pretest boot archive is documented in MAINTENANCE_LOG.md. Atomic rename/fsync on
FAT reduces update hazards but does not make the filesystem immune to power loss.

## Everyday use

The profile uses Fish with the shared Pure, autopair, fishbang,
fish-you-should-use, sponge, and async-prompt plugins. It includes Git/LFS,
the shared Emacs/mu4e configuration, Node/npm, Pi, and Syncthing. Run `emacsclient -t` (`M-x mu4e` for mail, `M-x ix-pi` for Pi),
or use `pi` directly. npm global installs use `~/.local`, not the Nix store.
Mail credentials are local runtime files; no moby password-manager connection
is required. The native index is rebuilt locally. A five-minute update interval
is configured, but the last observed timer was inactive and the operator chose
to defer investigation; automatic cadence is not claimed as verified.
The shared Trash-only permanent-deletion guard requires explicit
confirmation. Archive-import receipts were copied consistently; the complete
mail pipeline uses local credentials, not a moby vault. Google Calendar
integration/timers and its agenda entry were removed; personal files retained.

GitHub HTTPS authentication uses the declarative Home Manager `gh` credential
helper. After activating this profile, Git reuses your existing `gh auth login`
credentials; no `gh auth setup-git` is needed. The Git config is Nix-managed and
read-only, while GitHub login credentials remain in private runtime state, never
in the repository or Nix store. Run Git commands from the repository directory.

For Home Assistant, use the pinned alias above on the browser's computer:

```sh
ssh -NT -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
  -L 127.0.0.1:8123:127.0.0.1:8123 ix
```

Open `http://127.0.0.1:8123/` (both ends now use Home Assistant's default port).
The older local port `18123` is no longer needed. Keep the command running;
`-f` backgrounds SSH but does not automatically reconnect it after a disconnect.
Test from the browser's computer with
`curl -fLsS --max-time 10 -o /dev/null -w 'HTTP %{http_code}\n' http://127.0.0.1:8123/`.
If SSH reports an occupied port, inspect the listener before stopping anything;
an existing SSH process may also carry unrelated forwards.

For Syncthing, optionally run a separate tunnel in another terminal:

```sh
ssh -NT -o ExitOnForwardFailure=yes -L 127.0.0.1:18384:127.0.0.1:8384 ix
```

Open `http://127.0.0.1:18384` for Syncthing. Syncthing and HA's backend remain
loopback-only; HA additionally has the narrowly scoped LAN endpoint below.
HA has no imported accounts/device state; configure desired integrations in
its UI and add their Nix dependencies explicitly (`met` and `roborock` are
included). HA 2026.9 owns accepted HTTP settings in `.storage/http`; YAML is
only the initial migration input, so verify the actual listener after changing
settings.

### Home Assistant phone / home-LAN access

Enter `http://<ix-LAN-IPv4>:8124` manually in the official Home Assistant app.
The current DHCP address is `192.168.1.162`, hence
`http://192.168.1.162:8124`. This is not a static lease: check `ip -4 addr show
end0` if it changes, or reserve its existing Ethernet MAC in the home router.
Automatic discovery remains disabled; allow the phone app local-network access
and use the regular home Wi-Fi, not an isolated guest network. The official
companion app requires `services.home-assistant.config.mobile_app = { };`,
which is explicitly enabled without `default_config`. Nix infers its Python
dependencies from that configuration key; successful startup exposes the
login-protected `/api/mobile_app/registrations` endpoint.

`home-assistant-lan.socket` binds IPv4 port 8124 specifically to `end0`, not
loopback, IPv6, or Tailscale. Its sandboxed `systemd-socket-proxyd` forwards HTTP
and WebSockets to the unchanged `127.0.0.1:8123` backend. The firewall permits
only IPv4 sources **and destinations** in `192.168.1.0/24` arriving on `end0`;
this is not a global allowed-port rule or a trusted-interface exemption.
Changing home subnets requires reviewing the explicit firewall rule in
`machines/ix/services.nix`. The Mac tunnel remains unchanged.

This endpoint is **HTTP, not HTTPS**: use only on trusted home LAN/Wi-Fi, retain
HA authentication (prefer MFA), and never port-forward it from the Internet.
For encrypted remote access, use a separately reviewed HTTPS/VPN endpoint.
Raw TCP forwarding means HA sees LAN clients as loopback: do not configure a
`trusted_networks` login bypass for loopback, and note that IP bans cannot
distinguish clients behind this endpoint.

The Nix configuration enables the socket and firewall rule on a normal
deployment. A service-only trial using units under `/run/systemd/system` and
an inserted firewall rule is temporary: reboot removes the runtime units/rule,
and reloading the old firewall configuration removes the trial rule. When a
reviewed normal deployment includes this configuration, remove trial unit
links (not the declarative `/etc` units), reload systemd, and ensure the socket
is active. See `~/.local/state/home-assistant/lan-activation.md` on ix for the
current trial's exact locations, verification, and rollback instructions.

Syncthing's Documents and Pi-session shares are intentionally paused pending
later Mac/tailnet reconciliation. That work was explicitly removed from the
migration completion gate. Do not enable discovery/relays or clone a Tailscale
identity to bypass enrollment. Peer addresses use Tailscale DNS names, not fixed
IPs. The device ID was emailed privately, not published here; the debrief lists
the local GUI-password location.

## Reader and relay services

Hindsight runtime state now lives on ix, with the Pi client pointed at
`http://127.0.0.1:8888` locally and `http://ix.tail5e510f.ts.net:8888` over the
tailnet. The service is intentionally skipped until a dedicated Codex OAuth file
exists at `~/.local/state/hindsight-codex/auth.json`; create it with:

```bash
install -d -m 0700 ~/.local/state/hindsight-codex
CODEX_HOME=~/.local/state/hindsight-codex codex login --device-auth
sudo systemctl restart podman-hindsight-api.service
```

`pi-msg` is configured for ix with a separate `pi-msg-ix.age` secret and
Tailscale-only ejabberd on `ix.tail5e510f.ts.net`. The user service is skipped
until the account-registration marker exists. After deployment and after choosing
the phone account password, run:

```bash
pi-msg-register-accounts
systemctl --user status pi-msg.service
```

Keep the moby relay secret as rollback until phone and bot logins are verified
against ix.

`ix-state-backup.timer` creates weekly encrypted archives under
`~/.local/share/syncthing/ix-backups/ix/`. These archives cover ix-owned Pi
sessions, Elfeed state, selected private Syncthing documents, Hindsight encrypted
backup archives, Syncthing identity/config, and `Documents/broad/org`; they do
not include Hindsight's live database. The `ix-backups` Syncthing folder is
paused/send-only until remote devices are explicitly reconciled and accepted.
Run an immediate backup with:

```bash
ix-state-backup-now
journalctl -u ix-state-backup.service
```

## DNS blocking

ix provides Pi-hole-like DNS blocking through Blocky on its Tailscale IPv4 only:
`100.114.49.10:53`. The HTTP status endpoint stays on `127.0.0.1:4000`.
Upstreams are Quad9 and Cloudflare DNS-over-HTTPS, and the initial denylist is
StevenBlack's hosts list with Tailscale domains allowlisted. No DHCP, router, or
Tailscale DNS setting points clients at ix yet, so rollback is immediate: keep
clients on their current resolvers or remove the client-side DNS setting being
tested. Blocky state under `/var/lib/blocky` is included in ix encrypted state
backups.

Test from a tailnet client before any rollout:

```bash
dig @100.114.49.10 example.com
dig @100.114.49.10 doubleclick.net
```

## Foundation defaults and migration boundary

- Two Nix build jobs/cores; 25% RAM zram; no physical swap or HDD TRIM.
- 1 GiB tmpfs `/tmp`; 256 MiB journal bound; no Bluetooth UART initialization.
- Minimal Bash/Git/Home Manager; no desktop, mail credentials, live databases,
  or application state were imported before the foundation passed.
- Source data stays on moby during copy-first migration. Documents and agent
  sessions are working-copy synchronization, not backups; do not synchronize
  credentials, mail indexes, or Hindsight's live database.
- Moby must stay running until all required migrations/services are verified
  and the final configuration/log/debrief are saved on the Pi.
