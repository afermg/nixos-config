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
- **Lighting:** six white-spectrum bulbs. BILRESA **1/2 control bedroom only**;
  **3/4 control living+kitchen**, with equal brightness for lit lamps. Bathroom is
  independent. Double-click cycles **Off / Medium / Full** within the group;
  the cross-group legacy scene is retired and living/kitchen has a100% Full scene.
  Manual adjustments automatically latch persistent **Manual** mode. Motion and
  clock changes cannot override it; top-long toggles living/kitchen's mode
  (bedroom has no motion mode). Global All off rearms bathroom Automatic after
  **5 seconds**; living/kitchen pauses **30 seconds** without changing its mode.
  Repeated presses restart both; later manual input still wins. Living/kitchen
  presets cycle all Mid → all High → living-only Mid → living-only High → Off,
  with kitchen off in the living-only scenes. White controls and
  Kelvin favourites remain; the redundant Rooms dashboard stays removed.
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
Git alone is insufficient. Mocked lighting tests are not physical button
validation. A physical owned vacuum-then-mop run has not been validated.

## Moby retirement

Moby no longer imports or enables Home Assistant; ix is the home controller.
The former standalone Moby module and its setup instructions have been removed.
This is a repository configuration change only: it does not stop a running Moby
service or delete `/var/lib/hass`. Applying the change to Moby requires a
separately approved system deployment; any retained application data remains
untouched. No ix deployment, state migration, onboarding or re-pairing is needed.
