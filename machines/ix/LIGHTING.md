# Home lighting on ix

## Using the controls

On home Wi-Fi, open **http://192.168.1.162:8124/** and use Home Assistant's
**Lights** section. The redundant Rooms dashboard and its layout/button-generation
code have been removed. Shared control entities and scripts remain available to
Lights and existing callers. Port8123 remains loopback-only; phone clients use8124.
Other user dashboards are preserved.

Four registered BILRESA remotes have independent control groups:

- **1 and2:** bedroom only; bathroom is independent.
- **3 and4:** living room + kitchen; brightness commands give all lit lamps in
  this group the **same level**, rather than preserving unequal percentages.
- Only **bottom long-press (all-off)** crosses groups, including the bathroom.
  Top long-press toggles the group's Automatic/Manual mode; bedroom has no motion
  automation, so its top-long action does nothing. Double-clicks cycle scoped
  the ordered presets below; unrelated explicit OFF scene members are rejected.

Each remote uses this mapping:

| Button | Short press | Double-click | Long press |
| --- | --- | --- | --- |
| Top | Group brighter (×1.25), enter Manual | Next ordered preset / Off | Toggle group's Automatic/Manual mode |
| Bottom | Group dimmer (×0.8), enter Manual | Previous: reverse cycle | All six off; both motion zones Auto after 2min |

Commands never include smart-plug outlets, appliances or ix. Brightness changes
only currently lit, available, dimmable bulbs and preserve white temperature.
Living/kitchen uses one level derived from its brightest lit lamp, capped at255;
this corrects unequal levels even at the maximum. Bedroom lamps retain their
relative brightness. Off bulbs stay off during relative dimming. An explicit
manual adjustment latches Manual mode, preventing motion from undoing it.

Device names and all eight event IDs were verified against HA's registry.
Exact bindings live in `lighting-policy.nix` under `bilresa`; no name/area wildcard
can attach an unrelated remote. This work does not pair or remove devices.
Mocked button tests are not physical button validation.

Only fresh `multi_press_1`, `multi_press_2` and `long_press` state events are
accepted. Initial, restored, stale, repeated-timestamp, unsupported multi-press
and long-release events do not execute lighting commands.

## Automatic / Manual mode and the separate manual Off cooldown

The independent settings are `input_select.lighting_mode_living_kitchen` and
`input_select.lighting_mode_bathroom`, with **Automatic** and **Manual** options.
New helpers default Automatic; existing selections restore across restarts.
Bedroom has no motion automation and cannot change the bathroom's mode.

A deliberate nonzero brightness adjustment (number slider, white-control level,
native HA light control or BILRESA dimming) **automatically enters Manual** in
only the affected motion zone. Manual On, white-temperature and scene commands
also take persistent manual ownership. Explicit Off instead
starts the temporary cooldown below. Motion, vacancy recovery and midnight/07:00 profile
changes cannot change lamps in Manual. Selecting Manual itself leaves lamps alone.
Return explicitly to Automatic using the mode setting or top-long on remote3/4;
current occupancy/lux is then reevaluated without requiring a new motion edge.
Bathroom's mode is separate, available in HA's helper settings.

**Explicit manual Off rearms Automatic behind a two-minute (120-second)
cooldown in only the affected motion zones.** This includes room/group Off,
the Off stage in preset cycling, slider zero and direct human `light.turn_off`
for any allowlisted lamp. Another Off restarts the affected deadline. Bedroom
has no motion zone. A partial living/kitchen Off pauses that whole motion zone
but switches off only the requested lamps; it does not turn off other rooms.

Global **All off** (remote bottom-long, app script or native all-six Off) uses
this same path for both zones and switches all six lamps off. At expiry, current
occupancy/darkness is reevaluated, including motion already present; no new motion
edge is required. Empty/bright rooms stay off. Automatic vacancy shutoff, ambient
changes and incidental OFF members of a mixed scene never start this cooldown.
Later manual brightness, On, temperature, scene or explicit Manual selection
still wins and is not erased by expiry. Such input does not extend/cancel a timer.
Timers restore remaining time, including offline expiry. No automation is
disabled and no blocking script delay is used.
Changing mode does not cancel the timer; the compatibility service
`script.lighting_resume_automatic` explicitly returns selected zones to Automatic
and cancels their timers early (`room: all` is an explicit global resume).

All mode, cycle, manual and automatic decisions use one queue. Native human
service calls are distinguished from automated/child-context feedback. Absolute
native brightness requests and native scene requests are reapplied inside that
queue after selecting Manual, so an already in-flight automatic write cannot
win. Automatic reports never select Manual. No sensor timestamps are fabricated.

Native HA scenes can propagate the same human context to their lamp commands.
One queued native event router records validated scene contexts before waiting
on the shared lighting queue, so incidental scene Off remains Manual rather than
starting a cooldown. Its process-local `input_text.lighting_native_scene_contexts`
starts empty on HA startup; six full context IDs and a monotonic evicted-timestamp
cutoff bound storage without forgetting delayed scene subcalls. Fresh independent
Off still works after many scenes. Malformed/unknown contexts, or contexts at or
before the cutoff (including same-millisecond ambiguity), conservatively remain
Manual. This narrow edge case may require explicit Resume; no time window blindly
suppresses all subsequent Off commands.

In Automatic, the existing strict40lux living/kitchen and50lux bathroom rules,
ambient validation, Matter rounding tolerance and owned vacancy shutoff remain.
Unknown/unavailable mode or timer helpers fail closed. Existing manual/All-off
booleans retain their identities as ownership bookkeeping; the mode selector is
the persistent authority. Timer expiry never clears it. The legacy global
`lighting_manual_override` remains unused. Invalid/empty commands do nothing.

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

Moving a slider above zero selects Manual, so automatic lighting cannot move it back.
Bathroom's **20% night / 80% day**,2700K profile applies only in Automatic mode.
Off, unavailable and unlisted lamps are not included in proportional adjustments.

## Editable scenes

Bedroom keeps **Off → Medium (~50%) → Full (100%) → Off**.
Living/kitchen cycles **Off → all three Mid → all three High → living-room-only
Mid → living-room-only High → Off**. Kitchen is explicitly off in the last two
presets. Bottom double-click reverses the sequence. Selection and dispatch are
serialized together.

Scenes are editable under **Settings → Automations & scenes → Scenes**.
`lighting-scenes.nix` includes `/var/lib/hass/scenes.yaml` and seeds it only when
absent (including refusing to follow a dangling symlink). Later user edits are
not overwritten by seeding. The file is owned by hass and initially mode0600;
native scene-editor saves use0644 (the parent state directory remains private).
The scoped-lighting rollout narrows Bedroom medium via the supported editor API,
preserving its bedroom values and the other scene definitions.

The six supplied scenes are:

- **Bedroom - Medium illumination**: both bedroom lamps at 128/255 (~50%);
  other rooms unchanged. No color/temperature changes are requested.
- **Bedroom - Full illumination**: both bedroom lamps at **255/255 (100%)**;
  other rooms unchanged. No color/temperature change.
- **Living kitchen - Medium illumination**: all three living-room/kitchen lamps
  at **128/255 (~50%)**; bedroom and bathroom unchanged. No color change.

- **Living kitchen - Full illumination**: all three lamps at **255/255 (100%)**;
  bedroom and bathroom unchanged. No color change.

- **Living room only - Mid**: both living-room lamps at **128/255 (~50%)**,
  kitchen off; bedroom and bathroom unchanged.
- **Living room only - High**: both living-room lamps at **255/255 (100%)**,
  kitchen off; bedroom and bathroom unchanged.

The old cross-group **Living kitchen only** scene remains retired. The two new
living-only scenes have separate fixed IDs and must be added through the supported
scene-editor API on existing installations. Preserve all existing editable
presets; changing seeds alone does not modify `scenes.yaml`. Bathroom has no scene.

`sceneCycles` in `lighting-policy.nix` fixes each group's preset IDs and order;
labels no longer control membership. Every preset must be available and wholly
inside the selected group (including OFF members), otherwise cycling does nothing.
All lamps off means the Off stage, even if a scene was previously activated.
Otherwise the most recently activated preset determines the stage; without one,
next starts at the first Mid preset and previous at the last High/Full preset. Off is a scoped two-minute motion cooldown and
cannot immediately be undone by motion. Scene settings remain editable.

`script.bilresa_cycle_scenes` requires `room: bedroom` or `living_kitchen` and
accepts `direction: next` (default) or `previous`. It never controls bathroom.
Bottom long-press remains global All off, rearming bathroom and living/kitchen
Auto after two minutes.

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

Manual white adjustments select Manual and are not overwritten by bathroom's
scheduled profile. White controls do not cancel or extend a manual Off countdown
and do not enable Party mode. A multicolour Party mode is not supported by
these bulbs. No lamp commands are sent during installation.

## Automatic motion lighting

Only in Automatic mode, with an idle manual Off timer, `motion-lighting.nix`
uses the following rules:

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
  applies during qualifying Automatic occupancy, never over Manual mode.
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
it immediately, even if the manual helper was restored on across a restart,
**except when the separate manual Off hold is set**.

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

The matching HA runtime tests use disposable registries, real HA
triggers/conditions/scripts and mocked lamp services. All off tests cover
occupied motion, queued/in-flight commands, every motion entry route, real
time-controlled two-minute expiry, countdown restart, stale expiry races, restored/expired timers,
unknown timer state, manual On while paused, and all four remotes' scoped Resume.
Coverage also includes motion-condition cases and ordinary manual/native Off reversal,
late device reports, darkness/sensor recovery without new motion, in-flight
sensor changes, scene/brightness precedence,
no-feedback rounding, vacancy
recovery, slider zero/power-on, button-event guards and mappings, scene filtering/cycle,
brightness limits, combined-area targeting/common gain, room filtering,
room-specific scene membership, scoped manual ownership/resume, native human-vs-
automatic context filtering and brightness slider routing/readback. These are not
physical-device tests. Generated HA automation/script/scene schemas were also
validated before deployment; the live configuration check returns valid.

## Manual Off cooldown checkpoint — 2026-10-27

The two-minute rule above supersedes the five-second All off release below.
Deployed from `79wldbqsyd6gnj0z4dbh22vxqqxccgr9` to
`0fmx8hbiccvjsmjphkiw5hxyp56qfl44` using only supported input_text/timer/script/
automation reloads after narrow Nix activation. HA and protected processes stayed
running; SSH runtime files, scenes and existing registry identities were retained.
The separate native scene observer is no longer loaded; its registry entry remains.
The new queued native router handles both scene and direct-light events.

Both loaded timers are120seconds. The newer living **Manual** and bathroom
**Automatic** selections were preserved without Resume or other control commands.
No physical Off, scene or synthetic motion tests were performed. Forty-four focused
matching-HA tests passed, with HA/asyncio error capture; the existing synchronous
test lamp handler was marked `@callback` to eliminate its thread-dispatch errors.
The full emulated suite was not rerun.

Rollback is GC-rooted on ix at
`~/.local/state/ix-manual-off-20261027/rollback-system`.
Private evidence and incremental source patch on Oppy:
`~/.local/state/ix-motion-ssh-20261026-dqyLOw/manual-off-evidence/`.

## Living motion reactivation checkpoint — 2026-10-26

The living automation was already enabled and receiving real sensor events; its
persistent **Manual** mode (since October15) blocked motion, not a failed sensor.
All off now rearms both motion zones behind five-second pauses. Living retains
its calibrated strict40lux gate, ten-minute vacancy and brightness/color
preservation; it does not inherit bathroom's time-based brightness or50lux gate.
Later manual commands still win, including across restarts.

Deployed from the prior live baseline, not this checkout wholesale, to
`79wldbqsyd6gnj0z4dbh22vxqqxccgr9`. Only HA's configuration reload trigger changed;
HA and other service processes continued through supported timer/script/automation
reloads. One authorized living-only Resume selected Automatic; bathroom's Manual
mode was preserved. During the two-minute observation occupancy stayed clear,
so this verifies reactivation/configuration, not a new physical motion/lamp cycle.
No synthetic sensor events or test lamp commands were sent.

Rollback system `pdl00yw574qxgl69dxf4vw6i4wbad2bs` is retained on ix under
`~/.local/state/ix-living-reactivation-20261026/rollback-system`.
Private deployment/test evidence on Oppy:
`~/.local/state/ix-motion-ssh-20261026-dqyLOw/lighting-evidence/`.
Focused mocked HA modes, motion conditions, timer restore and All off tests passed;
the full emulated suite was incomplete, not a full-suite pass.

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
