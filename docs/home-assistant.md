# Home Assistant

## Current setup: ix

The home controller runs **Home Assistant Core on ix**, with configuration in
[`machines/ix/services.nix`](../machines/ix/services.nix). Nix manages services,
integration dependencies and lighting rules; HA keeps accounts, device identities,
editable scenes, dashboards and preferences in `/var/lib/hass`. This is not HA OS:
there is no Supervisor/add-on store. Preserve existing state; do not re-onboard or
re-pair devices when rebuilding.

- **Access:** home Wi-Fi uses `http://192.168.1.162:8124` (DHCP address). A narrowly
  scoped IPv4 LAN proxy forwards to `127.0.0.1:8123`; remote access uses a pinned
  SSH tunnel to ix. Keep HA authentication; do not expose these ports publicly.
- **Matter/Thread:** one ZBT-2 radio, native OTBR and Matter Server, with private
  runtime state and loopback management APIs. [`thread.nix`](../machines/ix/thread.nix)
  also provides the matching Matter OTA helper and Ethernet-scoped mDNS.
- **Lighting:** six white-spectrum bulbs. BILRESA **1/2 control bedroom+bathroom**;
  **3/4 control living+kitchen**, with equal brightness for lit lamps. Scenes and
  resume are group-scoped; bottom long-press remains global all-off, subject to
  occupied-motion priority. White-only controls replace the redundant Rooms
  dashboard. Favourite Kelvin presets are saved in HA's entity settings.
- **Motion:** living/kitchen turns on below **40 lux**, then off after **10 clear
  minutes**. Bathroom uses **20% midnight–07:00 / 80% otherwise**, at 2700 K in
  `America/New_York`, with a **five-minute** vacancy timer. Last-reported low lux
  remains usable when unchanged; an expired ambient sample no longer blocks motion.
- **History:** records all current appliance power/energy meters (fridge,
  TV/setup and Moby) plus every ALPSTUGA environmental measurement: **temperature,
  humidity, CO₂, PM2.5 and air-quality status**. Numeric measurements support
  long-term statistics; categorical air quality uses ordinary state history.
  New sensors accumulate history from inclusion onward, with no backfill.
  Earlier meter catch-up spikes do not represent instantaneous power surges.
- **Cleaning:** the **Cleaning** dashboard offers user-started whole-home
  vacuum-then-mop and cancel/dock. A fresh successful completion record—not merely
  docking—is required before mopping. No automatic start or restart resumption.
- **Sonos:** callbacks use TCP1400, restricted to the IPv4 home LAN on `end0`.

Details: [lighting](../machines/ix/LIGHTING.md),
[Roborock](../machines/ix/ROBOROCK.md), [ix access](../machines/ix/README.md).
The [backup proposal](../machines/ix/HOME_ASSISTANT_BACKUP.md) is **not a verified
consistent, off-device backup**. Protect HA, Matter and Thread state together;
Git alone is insufficient. The requested **Off → Medium → High** button cycle is
still pending: current double-clicks cycle eligible saved scenes in entity-ID order.
A physical owned vacuum-then-mop run has not been validated.

## Legacy standalone Moby configuration

The earlier minimal module remains available; it is not the current ix controller.
The NixOS module is [`machines/moby/home-assistant.nix`](../machines/moby/home-assistant.nix).
It runs Home Assistant Core as the `hass` system user, with the web UI and
Home Assistant's built-in helpers. It deliberately omits `default_config`:
no automatic network discovery, Bluetooth, Home Assistant Cloud, or history
recorder. Explicit dependencies are Met.no weather (used by onboarding) and
Roborock. You can remove the weather integration in the UI if unwanted.

This is a NixOS-managed Core installation, not Home Assistant OS: there is no
Supervisor or add-on store. Upstream does not officially support this installation
method; NixOS maintains the packaging. Add companion services through Nix later.

### First start

From the repository root on Moby, make the new module visible to Git-backed flakes
(if it is not already tracked), then rebuild:

```sh
git add machines/moby/home-assistant.nix
sudo nixos-rebuild switch --flake .#moby
```

This applies **all** current system configuration changes, not just Home Assistant.
A Home Manager switch alone will not install this system service.

Open <http://127.0.0.1:8123> on Moby and create your owner account. Choose your
home location and units during onboarding. From another computer, first run:

```sh
ssh -N -L 127.0.0.1:8123:127.0.0.1:8123 amunoz@moby.tail5e510f.ts.net
```

Then open the same URL on that computer while the tunnel remains running.
The intended listener is loopback-only, not LAN or direct Tailscale. Moby's
firewall is currently disabled, so do not change the HTTP listen address to
`0.0.0.0` or leave the listen-address list empty.

### HTTP settings migration (Home Assistant 2026.8+)

NixOS removed `services.home-assistant.openFirewall`; even setting it to `false`
now fails evaluation. Home Assistant moved HTTP settings from YAML into its
runtime storage/UI. The existing `config.http` block is kept temporarily so
upgrading from 2026.7 imports `127.0.0.1:8123` instead of losing that setting.

After the first upgraded start:

1. Open **Settings → System → Network → HTTP server**. Check that the listen
   addresses contain only `127.0.0.1` and the port is `8123`.
2. If asked to confirm the imported settings, confirm within **5 minutes**;
   otherwise Home Assistant reverts to its previous stored settings.
3. Verify the listener with `ss -ltn 'sport = :8123'` on Moby.
4. Only after confirming the migration, remove the `http` block from
   `machines/moby/home-assistant.nix` and rebuild. This clears the HTTP YAML
   deprecation/ignored-configuration repair notice.

After migration, edits to `config.http` no longer control the listener. Preserve
`/var/lib/hass/.storage` in backups; future HTTP changes belong in the UI. On a
fresh installation the initial migration may require prompt confirmation too.
If migration/binding fails, Home Assistant can fall back to an all-interface
listener, so do not assume that the YAML alone guarantees network isolation.
See the [HTTP integration documentation](https://www.home-assistant.io/integrations/http/).

### Add the Roborock QX Revo Plus

The official [Roborock integration](https://www.home-assistant.io/integrations/roborock/)
is the starting point for this Qrevo-family vacuum. Exact exposed features depend
on the model/firmware. Its dependencies are included in `extraComponents`.

1. Pair the vacuum with the **Roborock app**, not Xiaomi Mi Home, and confirm it
   works there.
2. Rebuild Moby to install the newly added integration dependencies:
   `sudo nixos-rebuild switch --flake /home/amunoz/.local/share/src/nixos-config#moby`.
3. In Home Assistant, go to **Settings → Devices & services → Add integration → Roborock**.
4. Enter your Roborock account email, leave the server region on **Auto** initially,
   and enter the verification code sent to that email.
5. Open the resulting device to see its vacuum, battery, map, and supported dock entities.

The Home Assistant API token is for external clients; it is **not** used to sign
into Roborock. Keep Roborock credentials in the integration's UI-managed storage,
not in Nix configuration.

Moby should be able to reach the vacuum's home-LAN address for reliable local
control (the integration uses TCP 58867 and UDP 58866). A DHCP reservation for the
vacuum is recommended. If Moby is elsewhere, the browser's SSH tunnel does not
connect it to the vacuum's LAN; establish routing or run Home Assistant at home.
Cloud fallback is not a substitute for reliable local connectivity, and cloud
access is still required for setup, maps, and other features. Do not forward
these device ports through the internet router.

### Customize incrementally

- For an integration configured through **Settings → Devices & services**, add
  its domain to `services.home-assistant.extraComponents`, rebuild, then configure
  it in the UI. For example: `extraComponents = [ "met" "roborock" "hue" ];`.
  This installs dependencies; it does not configure the integration. Without
  discovery, you may need to enter the device or bridge's address manually.
- YAML-configured integrations belong under `services.home-assistant.config`;
  NixOS automatically includes dependencies for integrations declared there.
- For local history later, add `recorder = { };` and `history = { };` under
  `config`. The default recorder uses SQLite; no separate database is needed.
- Before adding UI-edited automations, add
  `automation = "!include automations.yaml";` under `config` and initialize the
  file once with `sudo -u hass sh -c 'test -e /var/lib/hass/automations.yaml || printf "[]\n" > /var/lib/hass/automations.yaml'`.
  Keep that file writable rather than putting UI-edited automations in the Nix store.

Nix owns `configuration.yaml`; do not edit the generated file. Accounts,
dashboards, UI integration settings, and other runtime state live in
`/var/lib/hass` and persist across rebuilds. Back up that directory securely
(including `.storage`); it contains credentials. Do not put passwords or tokens
in Nix expressions, since the Nix store is readable by local users. Use a
runtime `secrets.yaml`/agenix setup when an integration needs YAML secrets.

### Check the service

```sh
systemctl status home-assistant
journalctl -u home-assistant -b --no-pager -n 100
curl -I http://127.0.0.1:8123/
```
