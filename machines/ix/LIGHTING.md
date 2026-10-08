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
stay off unless occupied darkness requires automatic lighting in that area.
At the shared maximum, Brighter makes no further increase.

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

## Motion priority, manual control and resume

**Occupied darkness wins immediately**, including while occupancy stays on.
A scene, room slider or All lights off cannot hold a motion-controlled area off
when its sensor reports occupancy and illuminance below50 lux. No new motion
transition, timer or explicit Resume is required. Bedroom has no motion rule;
bedroom-only commands do not change living/kitchen or bathroom ownership.

One shared queue serializes motion and wrapped manual operations. After every
manual command it reevaluates only the affected motion areas using current
sensor values. Eligible motion clears that area's manual flag, claims automatic
ownership and restores lighting. Neither motion automation nor BILRESA is ever
disabled by manual control. Scenes retain their editable definitions; priority
changes the resulting lamp state, not the saved scene.

Native scene/light requests can complete after their service-event listener.
Targeted lamp-state/attribute triggers close that race, including direct device
reports. Already-correct reports are ignored; bathroom brightness/temperature
checks tolerate Matter rounding to avoid feedback. No broad sensor-state
listener, polling-based activation or added turn-on delay is used.

Outside occupied darkness, manual ownership remains scoped to affected lamps,
including explicit OFF members of a scene. Unaffected rooms, appliance plugs
and unavailable/unknown sensors cannot acquire automatic priority. The persistent
helpers `input_boolean.lighting_manual_living_kitchen` and
`input_boolean.lighting_manual_bathroom` apply only until resumed or dark occupancy
wins. The legacy `lighting_manual_override` remains unused for compatibility.

**Resume motion here** clears just that area's manual ownership; top long-press
or **Resume automatic lighting** resumes both. Resume does not blindly toggle
all lamps. Native human light calls resolve entity/area/device/label targets
through the six-lamp allowlist; automatic calls cannot feed back into manual
ownership. Invalid/empty commands do nothing.

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

### Slider-only room controls

Each room has **one0–100% slider**, with no toggle or separate On/Off buttons.
Zero switches available room lamps off. Raising an entirely off room turns its
available lamps on at the requested level. Otherwise one common gain scales
only lit lamps, preserving colors and relative balance. Remote short presses
still scale lit lamps only; they do not wake an entirely off room.

The displayed template numbers (`number.ix_<room>_lighting_level`) derive their
value from the brightest lit lamp. A number slider is used because HA's native
light-brightness tile feature stops at1%, not zero. Existing
`light.ix_<room>_lighting_control` adapters remain for compatibility. Neither
adapter type is a physical device or an allowlist member. There is no state-sync
write loop; scenes, buttons and motion are reflected from actual lamp state.

Motion priority can immediately move the slider back: living/kitchen must be
on when dark and occupied; bathroom must be at its10%/2700K night setting.
Off, unavailable and unlisted lamps are not included in proportional adjustments
except when the separate, higher-priority motion rule requires the area on.

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
`direction: previous`. Both directions use the shared queue;
occupied darkness overrides conflicting scene settings immediately. Top long-press
or Resume clears non-priority manual ownership. Bottom long-press requests all
six lamps off, but dark occupied motion areas come back on.

Only nonempty scenes containing individual allowlisted lamps qualify. Scenes
with plugs, other entities, light groups or unavailable scene entities are
excluded. Loading, editing, labeling or validating a scene does not activate it.

## Automatic motion lighting

`motion-lighting.nix` gives occupied darkness priority over manual/scene settings:

- Living/kitchen MYGGSPRAY: occupancy
  `binary_sensor.myggspray_wrlss_mtn_sensor_occupancy`, illuminance
  `sensor.myggspray_wrlss_mtn_sensor_illuminance`. Below 50 lux, turn on the two
  living-room lamps and kitchen lamp, preserving brightness/color. Turn them off
  after **10 uninterrupted clear minutes**, only if automatically claimed.
- Bathroom MYGGSPRAY: Matter node21 (historical identifier16 is retained),
  occupancy/illuminance entity IDs with `_2` suffix. Below50 lux while occupied,
  enforce **10% / 2700 K**, even over an already-on manual scene. Turn it off after
  **5 uninterrupted clear minutes**, only if automatically claimed.

These vacancy timers are not motion turn-on delays. Invalid/unavailable lux
cannot turn lamps on; unavailable motion is not vacancy. Darkness gates turn-on,
not turn-off. New motion resets the clear interval. The ownership helpers
`input_boolean.myggspray_lighting_active` and
`input_boolean.myggspray_bathroom_lighting_active` are internal restored state,
not user controls.

Every-minute recovery checks retry eligible shutoffs and handle lost timers
across HA restarts. They do not independently turn lamps on. Restart establishes
a fresh clear interval, possibly followed by up to one recovery-check minute.
Non-priority manual control clears automatic ownership. Dark occupancy reclaims
it immediately, even if the manual helper was restored on across a restart.

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

The matching HA runtime passes all **41 lighting tests** without skips, using
disposable registries, real HA triggers/conditions/scripts and mocked lamp services.
Coverage includes45 motion-condition cases, immediate manual/native Off reversal,
late device reports, darkness/sensor recovery without new motion, in-flight
sensor changes, scene/brightness precedence,
no-feedback rounding, vacancy
recovery, slider zero/power-on, button-event guards and mappings, scene filtering/cycle,
brightness limits, combined-area targeting/common gain, room filtering,
room-specific scene membership, scoped manual ownership/resume, native human-vs-
automatic context filtering and brightness slider routing/readback. These are not
physical-device tests. Generated HA automation/script/scene schemas were also
validated before deployment; the live configuration check returns valid.

## Original expansion checkpoint — 2026-10-07

The latest immediate-priority/slider-only release record is
`~/.local/state/ix-motion-priority-20261008/` on Oppy. The preceding room-toggle
release is `~/.local/state/ix-toggle-lighting-20261008/`; scoped manual ownership
was introduced in `~/.local/state/ix-scoped-lighting-20261008/`. The earlier combined-control
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
a test. Later checks since Atuin removal have shown no new matching storage/USB
faults; the historical incident's exact cause is not established.

A background device audit found no definite stale devices to remove. Only the
explicitly excluded KLIPPBOK water sensor was unavailable. Nothing was deleted;
Matter removal would discard controller state and attempt physical unpairing.

Private evidence: `~/.local/state/ix-lighting-expansion-20261007/` on Oppy.
