# ALPSTUGA clock synchronization on ix

[Upstream Matter Time Sync](https://github.com/Loweack/Matter-Time-Sync) is packaged
in `services.nix` using `services.home-assistant.customComponents`. Version 2.2.2
is pinned by commit and source hash; no HACS or runtime pip install is needed.
Nix owns the installed component; Home Assistant owns its UI configuration.

## Configuration

After deploying, add **Settings → Devices & services → Add integration →
Matter Time Sync** (only once), with:

- WebSocket: `ws://127.0.0.1:5580/ws` (the existing Matter integration's server).
- Timezone: `America/New_York`, matching Home Assistant.
- Device filter: `alpstuga`; filter target: `any`.
- Automatic synchronization: enabled, every **60 minutes**.
- Only devices supporting time synchronization: enabled.

No extra firewall rule is needed. The Matter management API must stay private.
This syncs the clock and timezone, not the display's clock/air-quality mode.
After a device power loss, the next successful hourly sync restores its time;
use the sync button for immediate correction. If HA's timezone changes, also
update this integration's timezone in **Configure**: it is copied during setup,
not continuously inherited.

The ALPSTUGA currently has Matter node ID **2**. Its generated button is
`button.matter_time_sync_sync_time`; check the `node_id` and `device_name`
attributes instead of assuming that the entity ID contains `alpstuga`.
Press it and confirm `last_sync_result: success` and a new `last_synced` value.
`matter_time_sync.sync_all` uses the configured filter; `sync_time` targets an
explicit node. Do not copy node IDs from community examples.

## Display-content control is not exposed

On ALPSTUGA firmware **1.0.26**, HA exposes
`switch.alpstuga_air_quality_monitor_display` for screen **on/off**, not clock
versus air-quality mode. Fresh Matter descriptor/attribute/command reads on
2026-10-06 found no content-mode control, including advertised vendor-specific
controls. Time synchronization does not add one. Do not create an on/off
"mode-switch" automation: it would not implement the requested behavior.

The requested clock-by-default/manual-readings button is therefore blocked for
the physical display with the currently exposed interface. A dashboard button
showing the sensor readings is a separate possible UI, not device control.
Undocumented commands and physical-button auto-return behavior remain unverified.
See also [HA's display-switch discussion](https://github.com/home-assistant/core/issues/158943).

## Verification and maintenance

On 2026-10-06, version 2.2.2 was deployed through the normal NixOS generation.
A manual button press successfully synchronized node 2; Thread, OTBR, Matter,
and Matter Time Sync all reported `loaded`. The integration's hourly timer is
enabled. The deployment preserved the existing kernel and Home Manager unit.
No pairing, Thread network, credentials, or firewall settings were changed.

Upstream currently emits a device-registry API deprecation warning scheduled
to become an error in **Home Assistant 2027.9**. Review upstream compatibility
before that upgrade; pinning the component is not a compatibility guarantee.

Private deployment/rollback evidence on ix is under
`~/.local/state/matter-time-sync/`. The pre-change config-entry snapshot is
root-only. Normal removal is via HA's integration UI, then removal of the Nix
`customComponents` entry and a reviewed rebuild. Do not overwrite `.storage`
while HA is running.
