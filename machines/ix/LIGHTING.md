# Home lighting on ix

## Using the controls

On home Wi-Fi, open **http://192.168.1.162:8124/room-lighting/rooms** or choose
**Room lighting** in Home Assistant's sidebar. Port 8123 is loopback-only on ix;
phone clients must use 8124. Existing dashboards are preserved.

Both registered bedroom BILRESA remotes use the same mapping:

| Button | Short press | Double-click | Long press |
| --- | --- | --- | --- |
| Top | Brighter (×1.25) | Next Button scenes scene | Resume automatic lighting |
| Bottom | Dimmer (×0.8) | Previous Button scenes scene | All six lamps off |

Commands never include smart-plug outlets, appliances or ix. Brightness changes
only currently lit, available, dimmable bulbs, preserving color and relative
brightness. A common multiplier is capped before rounding so the brightest bulb
cannot exceed 255; individual bulbs are not clipped independently. Off bulbs
stay off. At the shared maximum, Brighter makes no further increase.

Physical button behavior has not been exercised by the deployment tests. The
current registrations are Matter nodes **23 and 24**, both available at the
post-change inventory check. Former node22 disappeared and node24 was registered
before activation, outside this deployment. No pairing was removed or created by
this work. The event entity IDs remain:

- Top: `event.bedroom_bilresa_dual_button_1_button_1` and
  `event.bilresa_dual_button_button_1`.
- Bottom: `event.bedroom_bilresa_dual_button_1_button_2` and
  `event.bilresa_dual_button_button_2`.

Only fresh `multi_press_1`, `multi_press_2` and `long_press` state events are
accepted. Initial, restored, stale, repeated-timestamp, unsupported multi-press
and long-release events do not execute lighting commands.

## Manual control and resume

Manual ownership is **per motion-controlled area**, based on the actual lamps
being commanded, not the scene's name. Bedroom-only actions do not pause either
motion sensor. Living/kitchen commands pause only that combined area; bathroom
commands pause only the bathroom. A scene with explicit OFF targets in another
area also takes manual control there. All-six-off intentionally pauses both.
Global brightness commands pause only areas containing lamps that are actually
lit and adjusted. Invalid/empty/no-lit commands never acquire ownership.

For each affected area, the shared router sets its persistent manual helper,
stops only that area's in-flight/queued motion actions, clears its ownership,
and immediately re-enables its automation. The automation stays enabled, but its
manual condition blocks automatic actions until resumed. Unaffected automations
and ownership are untouched. Both motion and BILRESA automations start enabled;
manual operations never target the BILRESA automation for disabling.

The helpers are `input_boolean.lighting_manual_living_kitchen` and
`input_boolean.lighting_manual_bathroom`; no initial values, so pauses survive
restarts. The old `lighting_manual_override` entity is retained for identity
compatibility, explicitly marked unused, and never gates motion.

**Resume motion here** clears only that area's pause and reevaluates its current
occupancy/darkness. **Resume automatic lighting** or top long-press resumes both.
`script.lighting_resume_automatic` accepts an optional `room` argument. No added
motion turn-on delay; resume does not blindly turn every lamp on or off.

Native safe `scene.turn_on` requests and direct human `light.turn_on`, `turn_off`
or `toggle` requests also acquire scoped ownership. Entity, area, device and
label targets are restricted to the known lamps. The light listener requires a
human user context: automatic motion light calls cannot pause themselves. These
listeners run alongside native requests; wrapped controls guarantee pause before
the lamp command. Neither listens to every sensor-state update.

All dashboard/button manual operations share a serialized queue. The dashboard
has **Bedroom**, **Living room + kitchen**, and **Bathroom** controls. Living room
and Kitchen remain separate HA areas with unchanged device assignments. The
combined `living_kitchen` lighting zone automatically gathers lamps assigned to
either area, intersects them with the six-lamp allowlist, and controls the three
lamps together. Brightness uses one common gain across both areas, not separate
room gains. On/Off does not change bedroom or bathroom lamps.

Area membership is read at command time through `roomAreas` in
`lighting-policy.nix`; no merged HA area or new physical/group device is created.
Existing script calls using `living_room` or `kitchen` remain compatible, while
selectors/dashboard expose one combined control. Adding a new lamp still requires
explicitly extending the allowlist; appliance plugs cannot enter the group.

### Brightness sliders

Each control now has a native HA brightness slider instead of Dimmer/Brighter
buttons, with separate On/Off buttons retained. Three template light entities
(`light.ix_<room>_lighting_control`) are UI adapters, not physical devices or
members of the allowlist. They derive their state/level from the real lamps,
so buttons, scenes and motion are reflected without feedback/state-sync loops.

The slider represents the brightest lit lamp, scaling all lit room lamps with
one gain while preserving color and relative balance. Off lamps stay off; use
**On** first if the whole room is off. The remote's short-press brighter/dimmer
behavior remains unchanged. Room membership still comes from the separate HA
area assignments.

## Editable scenes

Scenes are editable under **Settings → Automations & scenes → Scenes**.
`lighting-scenes.nix` includes `/var/lib/hass/scenes.yaml` and seeds it only when
absent (including refusing to follow a dangling symlink). Later user edits are
not overwritten by seeding. The file is owned by hass and initially mode0600;
native scene-editor saves use0644 (the parent state directory remains private).
The scoped-lighting rollout narrows Bedroom medium via the supported editor API,
preserving its bedroom values and the other scene definitions.

The four supplied scenes are:

- **Bedroom - Medium illumination**: both bedroom lamps at 128/255 (~50%);
  other rooms unchanged. No color/temperature changes are requested.
- **Living kitchen only**: living-room lamps at 204/255 (~80%), kitchen at
  128/255 (~50%); bedroom and bathroom lamps off. No color changes are requested.

- **Bedroom - Full illumination**: both bedroom lamps at **255/255 (100%)**;
  other rooms unchanged. No color/temperature change.
- **Living kitchen - Medium illumination**: all three living-room/kitchen lamps
  at **128/255 (~50%)**; bedroom and bathroom unchanged. No color change.

The two added scenes are installed using HA's scene-editor API without replacing
existing scene definitions. All four are labeled **Button scenes**. Add that
label to another editable scene to
include it in the double-click cycle. Candidates are sorted by entity ID; next
and previous move relative to the most recently activated candidate, wrapping
at either end. With no previous activation, next selects the first candidate
and previous selects the last. A single candidate selects itself; zero eligible
candidates performs no command and does not pause motion.

`script.bilresa_cycle_scenes` accepts `direction: next` (the default) or
`direction: previous`. Both directions take manual control before activation;
**top long-press** or the dashboard Resume button restores automatic lighting.
Bottom long-press retains all-six-lamps-off.

Only nonempty scenes containing individual allowlisted lamps qualify. Scenes
with plugs, other entities, light groups or unavailable scene entities are
excluded. Loading, editing, labeling or validating a scene does not activate it.

## Automatic motion lighting

`motion-lighting.nix` retains the existing rules when manual control is off:

- Living/kitchen MYGGSPRAY: occupancy
  `binary_sensor.myggspray_wrlss_mtn_sensor_occupancy`, illuminance
  `sensor.myggspray_wrlss_mtn_sensor_illuminance`. Below 50 lux, turn on the two
  living-room lamps and kitchen lamp, preserving brightness/color. Turn them off
  after **10 uninterrupted clear minutes**, only if automatically claimed.
- Bathroom MYGGSPRAY: Matter node21 (historical identifier16 is retained),
  occupancy/illuminance entity IDs with `_2` suffix. Below 50 lux, if the bathroom
  lamp is initially off, turn it on at **10% / 2700 K**. Turn it off after
  **5 uninterrupted clear minutes**, only if automatically claimed. An already-on
  manual bathroom lamp is not dimmed or claimed.

These vacancy timers are not motion turn-on delays. Invalid/unavailable lux
cannot turn lamps on; unavailable motion is not vacancy. Darkness gates turn-on,
not turn-off. New motion resets the clear interval. The ownership helpers
`input_boolean.myggspray_lighting_active` and
`input_boolean.myggspray_bathroom_lighting_active` are internal restored state,
not user controls.

Every-minute recovery checks retry eligible shutoffs and handle lost timers
across HA restarts. They do not independently turn lamps on. Restart establishes
a fresh clear interval, possibly followed by up to one recovery-check minute.
Manual takeover clears ownership and suspends those rules until explicit resume.

## Source and tests

`services.nix` imports `motion-lighting.nix`, `lighting-scenes.nix`,
`room-lighting.nix` and `bilresa-lighting.nix`; `lighting-policy.nix` is their
shared lamp allowlist. Automations/scripts/dashboard structure remain Nix-managed;
the scene definitions themselves are HA-editable.

```sh
python3 -B -m unittest discover -s machines/ix/tests -p 'test_*lighting*.py'
IX_HA_DEPENDENCY_HELPER=~/.local/state/matter-time-sync/configure-energy.py \
  python3 -B -m unittest discover -s machines/ix/tests -p 'test_*lighting*.py'
```

The matching HA runtime passes all **36 lighting tests** without skips, using
disposable registries and mocked services. Coverage includes the existing 38
motion-condition cases, button-event guards and mappings, scene filtering/cycle,
brightness limits, combined-area targeting/common gain, room filtering,
room-specific scene membership, scoped manual ownership/resume, native human-vs-
automatic context filtering and brightness slider routing/readback. These are not
physical-device tests. Generated HA automation/script/scene schemas were also
validated before deployment; the live configuration check returns valid.

## Original expansion checkpoint — 2026-10-07

The latest scoped-manual/slider release record is
`~/.local/state/ix-scoped-lighting-20261008/` on Oppy. The earlier combined-control
release is in `~/.local/state/ix-combined-room-20261007/`. The preceding double-click
revision is in `~/.local/state/ix-bilresa-doubleclick-20261007/`. The following
is the original expansion's historical checkpoint, not a claim that its hash is
still the newest generation.

Original expansion generation: `8br4nj08xcs006aji52a2l01r1fyh5mj`; previous generation
`mzgdcykxnd23msnk06rbv3vcn5jclbq6` remains the rollback baseline. No host reboot.
Only `home-assistant.service` changed (configuration trigger and scene initializer);
boot, Home Manager and other unit definitions were unchanged. The reviewed source
is isolated under `~/.local/state/ix-lighting-expansion-20261007/source` on Oppy.
**Do not blindly deploy either whole dirty checkout**: real source still contains
a pending six-sensor Recorder policy; this release preserves the running two
fridge sensors and unrelated services.

Warn before HA downtime. NixOS HA reload is SIGHUP/restart, not an automation-only
reload. Allow up to ten minutes for normal imports/integration startup, but act
on explicit errors. Verify authenticated RUNNING **outside recovery/safe mode**,
required entities, dashboard, editable scene API and LAN access—not just HTTP200
or systemd active.

The first switch start missed scene-file initialization and entered recovery
mode. One HA-only restart using the now-loaded new unit initialized the file and
restored normal operation. NixOS switch also retried the pre-existing failed
Ejabberd service and exited4 for its database failure; no XMPP repair or further
retry was performed. A dry activation listed only HA and did not reveal that
retry. Do not blindly repeat the full switch to clear its exit status.

Live verification confirmed owner access, nine scripts, four enabled automations,
the dashboard, both editable scenes, Button scenes label membership, and retained
button entity identities. No scenes, lamps or synthetic motion were activated as
a test. Kernel checks found no fresh matching storage faults, but the underlying
historical disk/USB problem remains unresolved.

A background device audit found no definite stale devices to remove. Only the
explicitly excluded KLIPPBOK water sensor was unavailable. Nothing was deleted;
Matter removal would discard controller state and attempt physical unpairing.

Private evidence: `~/.local/state/ix-lighting-expansion-20261007/` on Oppy.
