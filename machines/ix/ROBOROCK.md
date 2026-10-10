# Whole-home vacuum, then mop

**Home Assistant → Cleaning** (`/flat-cleaning/roborock`) has:
- **Vacuum, then mop** (confirmation required).
- **Cancel sequence & dock** (only affects an active sequence).
- Sequence status, battery, progress and ordinary robot controls.

Nothing starts on installation, HA startup or a schedule.

## Behaviour

Uses the original `vacuum.roborock_qx_revo_plus` and its existing Roborock
integration/coordinator. No second account/client, copied credentials, new fabric,
map edits, room customisation changes, schedules or factory resets.

Start requires docking/charging, no unfinished cleaning/return job, a known
current map, at least 50% battery, mop/water box attached and healthy water/dock
sensors. The standard Roborock **vacuum** mode selects balanced suction, water
off and standard route. Explicit `app_start` starts the entire current map—not
HA's context-dependent resume-a-room behaviour.

The next pass requires an observed running job plus a **new cleaning record**:
its start must differ from the previous record and fall within this command's
request/acknowledgement window (with30 seconds clock tolerance), start type2
(app command), completion must be1, error0, clean type1
(whole map), and finish reason one of the SDK's successful completion codes.
It must match the map, and the robot must report no unfinished job and return
to charging. Docking for a recharge or mop wash is NOT completion. Progress100%
alone is also NOT completion. A four-hour deadline applies to each pass, with
no automatic retry.

After vacuum completion, waits for at least30% charge, then selects standard
**mop-only** mode and starts a separate whole-map pass. Native no-go/no-mop
areas and carpet handling remain the robot's responsibility. After both passes
succeed and the robot is back at the dock, restores prior fan/water/route settings.
On cancellation/failure these preferences may remain at the last selected mode;
there are no surprise recovery commands or automatic retries.

Pause, error, unavailability, map/cleaning-mode changes or another HA vacuum
command cancel the follow-up. Cancel stops an active sequence and sends Stop
then Dock. HA shutdown cancels pending follow-up but does not forcibly stop the
robot's autonomous current pass. Restart never resumes a sequence. Check the
Roborock app before restarting manually if a pass was interrupted.

## Implementation / tests

`roborock-cleaning.nix` packages `ha-components/custom_components/ix_roborock_sequence`.
The small integration reuses native services for commands and reads the existing
coordinator's complete/error/finish fields, which the stock HA sensors do not
expose. Status is `sensor.ix_roborock_sequence`. `ix_roborock_sequence.inspect` is a
read-only response service; it does not issue a robot command.

Unit tests use a fake robot and a disposable matching-version HA instance. Test
coverage includes old/partial/cancelled/error records, recharge, timeout, offline,
mode/map changes, cancellation, duplicate start, restoration and setup sending
zero robot commands. Software/installation checks are not a physical two-pass
cleaning validation; the first real run is user-initiated.
