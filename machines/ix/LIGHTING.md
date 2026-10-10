# Home lighting on ix

## Using the controls

On home Wi-Fi, open **http://192.168.1.162:8124/** and use Home Assistant's
**Lights** section. The redundant Rooms dashboard and its layout/button-generation
code have been removed. Shared control entities and scripts remain available to
Lights and existing callers. Port8123 remains loopback-only; phone clients use8124.
Other user dashboards are preserved.

Four registered BILRESA remotes have independent control groups:

- **1 and2:** bedroom + bathroom.
- **3 and4:** living room + kitchen; brightness commands give all lit lamps in
  this group the **same level**, rather than preserving unequal percentages.
- Only **bottom long-press (all-off)** crosses groups. Top long-press resumes
  only the group's motion zone. Double-clicks select only scenes whose entire
  membership is inside the group; unrelated explicit OFF members also exclude a
  scene. Bathroom's automatic clock-based level still takes priority when occupied.

Each remote uses this mapping:

| Button | Short press | Double-click | Long press |
| --- | --- | --- | --- |
| Top | Group brighter (×1.25) | Next group-only Button scene | Resume group's automatic lighting |
| Bottom | Group dimmer (×0.8) | Previous group-only Button scene | All six lamps off |

Commands never include smart-plug outlets, appliances or ix. Brightness changes
only currently lit, available, dimmable bulbs and preserve white temperature.
Living/kitchen uses one level derived from its brightest lit lamp, capped at255;
this corrects unequal levels even at the maximum. Bedroom/bathroom retain their
relative brightness, except bathroom automatic priority. Off bulbs stay off
unless occupied darkness requires automatic lighting in that area.

Device names and all eight event IDs were verified against HA's registry.
Exact bindings live in `lighting-policy.nix` under `bilresa`; no name/area wildcard
can attach an unrelated remote. This work does not pair or remove devices.
Mocked button tests are not physical button validation.

Only fresh `multi_press_1`, `multi_press_2` and `long_press` state events are
accepted. Initial, restored, stale, repeated-timestamp, unsupported multi-press
and long-release events do not execute lighting commands.

## Motion priority, manual control and resume

**Occupied darkness wins immediately**, including while occupancy stays on.
A scene, room slider or All lights off cannot hold a motion-controlled area off
when occupied and the applicable ambient reading is below the zone's cutoff:
**40 lux for living/kitchen**, **50 lux for bathroom**. Living/kitchen uses current
lux; bathroom accepts a last-reported low reading and latches an owned dark cycle
while ON (see below). Missing or stale baseline metadata no longer blocks known
darkness, including takeover of a manually lit lamp. No new motion transition or explicit Resume is needed to reconcile an
already owned, occupied cycle. Bedroom has no motion rule;
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
listener or unconditional polling-based activation is used. Bathroom sampling
waits for an actual OFF-era report, not a guessed mode or the lamp's own light.

Outside occupied darkness, manual ownership remains scoped to affected lamps,
including explicit OFF members of a scene. Unaffected rooms, appliance plugs
and unavailable/unknown sensors cannot acquire automatic priority. The persistent
helpers `input_boolean.lighting_manual_living_kitchen` and
`input_boolean.lighting_manual_bathroom` apply only until resumed or dark occupancy
wins. The legacy `lighting_manual_override` remains unused for compatibility.

`script.lighting_resume_automatic` with a room clears just that area's manual
ownership; top long-press resumes only that remote's motion zone; an explicit all-room
script invocation resumes both. Resume does not blindly toggle
all lamps. Native human light calls resolve entity/area/device/label targets
through the six-lamp allowlist; automatic calls cannot feed back into manual
ownership. Invalid/empty commands do nothing.

All shared-control/button manual operations use a serialized queue. Controls
cover **Bedroom**, **Living room + kitchen**, and **Bathroom**. Living room
and Kitchen remain separate HA areas with unchanged device assignments. The
combined `living_kitchen` lighting zone automatically gathers lamps assigned to
either area, intersects them with the six-lamp allowlist, and controls the three
lamps together. Living/kitchen brightness controls apply one equal level to lit
members, derived from their brightest lamp rather than preserving unequal ratios. On/Off does not change bedroom or bathroom lamps.

Area membership is read at command time through `roomAreas` in
`lighting-policy.nix`; no merged HA area or new physical/group device is created.
Existing script calls using `living_room` or `kitchen` remain compatible, while
selectors expose one combined control. Adding a new lamp still requires
explicitly extending the allowlist; appliance plugs cannot enter the group.

### Shared brightness controls

Each room retains a **0–100% numeric brightness control**; no bespoke dashboard
or per-room card layout is generated.
Zero switches available room lamps off. Raising an entirely off room turns its
available lamps on at the requested level. Otherwise one common gain scales
only lit lamps, preserving white temperature; living/kitchen levels match, while
bedroom levels preserve relative balance. Remote short presses
still scale lit lamps only; they do not wake an entirely off room.

The retained template numbers (`number.ix_<room>_lighting_level`) derive their
value from the brightest lit lamp. A number slider is used because HA's native
light-brightness tile feature stops at1%, not zero. The obsolete
`light.ix_<room>_lighting_control` adapters were removed with Rooms after checking
saved-dashboard references. Their registry identities are retained and disabled,
not deleted. The number and white-control entities are not physical devices or
allowlist members. There is no state-sync
write loop; scenes, buttons and motion are reflected from actual lamp state.

Motion priority can immediately move the slider back: living/kitchen must be
on when dark and occupied; bathroom must use its clock-selected **20% night / 80% day**
setting, both at 2700K.
Off, unavailable and unlisted lamps are not included in proportional adjustments
except when the separate, higher-priority motion rule requires the area on.

## Editable scenes

**Pending:** the requested **Off → Medium → High** cycle has not yet replaced
entity-ID-ordered scene cycling. Do not interpret the current cycle as that order.

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
at either end. Physical remotes additionally require all scene members to be in
their own group. Thus **Living kitchen only**, which explicitly switches bedroom
and bathroom off, is not a group-safe remote scene; its original definition remains
available in the scene editor/UI. With no previous activation, next selects the first candidate
and previous selects the last. A single candidate selects itself; zero eligible
candidates performs no command and does not pause motion.

`script.bilresa_cycle_scenes` accepts `direction: next` (the default) or
`direction: previous`. Both directions use the shared queue;
occupied darkness overrides conflicting scene settings immediately. Top long-press
clears non-priority ownership only for the remote's group. Bottom long-press requests all
six lamps off, but dark occupied motion areas come back on.

Only nonempty scenes containing individual allowlisted lamps qualify. Scenes
with plugs, other entities, light groups or unavailable scene entities are
excluded. Loading, editing, labeling or validating a scene does not activate it.

## Per-room white temperature

The `light.ix_<room>_white_control` entities provide warm/cool white adjustment
in Lights. These are IKEA **WS (white-spectrum)** bulbs, not full RGB bulbs.
Advertised Matter XY support is not proof of a full physical colour gamut.
White-control entities expose **only white temperature**, not HS/RGB/XY controls.
HA2026.9 restores old capability/mode combinations even after configuration changes;
this caused startup/state-update errors on an obsolete Rooms adapter. Its source
is removed rather than editing restore-state storage. Dedicated white-control IDs
have consistent temperature-only modes; old registry records remain preserved.
The common white range is approximately2202–6535K. Favourite colours for the six
bulbs and three white controls are only Kelvin presets:2700,3000,3500,4000,5000,
6500K. No RGB, HS or XY colour presets are added.

Temperature commands use the same serialized room queue: only lit lamps change,
or all available lamps turn on if a temperature service call targets an entirely
off room. Brightness is preserved; off members of a partly lit room remain off.
The native temperature slider may require turning on the room via brightness
first. Bedroom controls never change living/kitchen or bathroom lamps.
Unknown/group/appliance targets remain excluded.

Motion priority is unchanged: occupied dark bathroom lighting can immediately
restore its automatic20%/80%,2700K profile. These controls do not enable Party mode
or suspend automatic lighting. A multicolour Party mode is not supported by
these bulbs. No lamp commands are sent during installation.

## Automatic motion lighting

`motion-lighting.nix` gives occupied darkness priority over manual/scene settings:

- Living/kitchen MYGGSPRAY: occupancy
  `binary_sensor.myggspray_wrlss_mtn_sensor_occupancy`, illuminance
  `sensor.myggspray_wrlss_mtn_sensor_illuminance`. **Strictly below 40 lux**, turn on
  the two living-room lamps and kitchen lamp, preserving brightness/color. Turn
  them off after **10 uninterrupted clear minutes**, only if automatically claimed.
  Calibrated on 2026-10-09: a fresh reading with all three lamps OFF was **42 lux**,
  which the user considered sufficient background light. At 40 lux or above,
  movement alone does not turn them on. Lamp-generated light after turn-on does
  not itself switch them off; the vacancy timer still applies.
- Bathroom MYGGSPRAY: Matter node21 (historical identifier16 is retained),
  occupancy/illuminance entity IDs with `_2` suffix. Brightness uses **only HA
  local time (America/New_York)**, never illuminance:

  | Local time | Automatic target |
  | --- | --- |
  | Midnight inclusive to before 07:00 | **20% / 2700 K** |
  | 07:00 inclusive to before midnight | **80% / 2700 K** |

  Midnight and07:00 triggers update an occupied automatic cycle without needing
  another motion edge. They do not turn on an empty bathroom. The target still
  wins over manual commands/scenes during qualifying occupancy.
  The existing **lamp-off ambient below50lux** rule gates automatic activation
  only; it does NOT choose low/high brightness. Turn off after **5 uninterrupted
  clear minutes**, only if automatically claimed.

**Unchanged lux is not an unavailable sensor.** On2026-10-10, the old30-minute
sample expiry blocked motion despite the lamp staying OFF and the sensor reporting
1lux for four hours. Activation now accepts available, non-restored
**last-reported** lux below50, even if unchanged for hours or the lamp is already
manually ON (a low reading with the lamp lit also indicates darkness). This is
explicitly not evidence of a fresh measurement. Bright/invalid/unavailable readings
still cannot activate it. Once motion owns a cycle, lamp-generated lux cannot
cancel that cycle; the vacancy timer ends ownership and brightness follows time.

`input_text.bathroom_lighting_ambient` remains a separate, strictly timestamped
OFF-sample record: confirmed OFF, report at least two seconds after OFF and after
HA startup, at most30minutes old at capture. Cached startup data are never written
as fresh samples. When a **manually lit, unowned** lamp has a HIGH current lux
reading, inferring dark ambient still needs a recent confirmed dark OFF sample. Sampling never switches
lamps off or fabricates sensor values. A brief manual OFF does not discard an
already owned cycle's priority.

An OFF-only observer handles lux changes, settled OFF, startup and a ten-second
check for same-value sensor reports. It can reconcile occupancy only after a
**new valid sample**; unchanged/stale polls cannot turn lights on. It shares the
same serialized queue as manual/motion actions, including sampling before manual
ON commands. The existing minute vacancy-recovery check remains OFF-only.

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
