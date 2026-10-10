"""Bounded vacuum-then-mop controller. No networking or credentials here."""
import asyncio
import time

FINISHED = {52, 54, 55, 56, 57}
DOCKED = {"charging", "charging_complete"}
BAD = {"paused", "error", "charging_problem", "device_offline", "updating", "shutting_down"}

class SequenceError(Exception):
    """Fail closed: never infer completion from a docking transition."""


def completed(record, previous, requested, map_id, latest_start=None):
    """Require a NEW successful whole-home job, not an old/partial record."""
    if not record or record.get("begin") == previous:
        return False
    begin, end = record.get("begin"), record.get("end")
    return (
        isinstance(begin, (int, float)) and isinstance(end, (int, float))
        and requested - 30 <= begin <= (latest_start if latest_start is not None else requested + 30) and end > begin
        and record.get("complete") == 1 and record.get("error") == 0
        and record.get("clean_type") == 1 and record.get("start_type") == 2
        and record.get("finish_reason") in FINISHED
        and record.get("map_flag") in (None, map_id)
    )


class Runner:
    def __init__(self, read, command, report, *, sleep=asyncio.sleep,
                 monotonic=time.monotonic, wall=time.time):
        self.read, self.command, self.report = read, command, report
        self.sleep, self.monotonic, self.wall = sleep, monotonic, wall
        self.abort_reason = None
        self.expected_mode = None
        self.map_id = None
        self.last_record = None
        self.stage = "idle"

    def status(self, phase, message):
        self.stage = phase
        self.report(phase, message)

    def check(self):
        if self.abort_reason:
            raise SequenceError(self.abort_reason)
        s = self.read()
        if not s["available"] or s["state"] in BAD or s["error"] != 0:
            raise SequenceError("Robot unavailable, paused or reporting an error; follow-up cancelled")
        if self.map_id is not None and s["map"] != self.map_id:
            raise SequenceError("Map changed; follow-up cancelled")
        if self.expected_mode and s["mode"] != self.expected_mode:
            raise SequenceError("Cleaning mode changed externally; follow-up cancelled")
        return s

    def ready(self):
        s = self.check()
        if s["state"] not in DOCKED or s["in_cleaning"] != 0 or s["in_returning"] != 0:
            raise SequenceError("Start from the dock with no unfinished job")
        if s["map"] is None or not s["mop_ready"] or s["battery"] < 50:
            raise SequenceError("Need a known map, at least 50% battery, attached mop/water box and no water/dock fault")
        return s

    async def phase(self, mode):
        s = self.check()
        if s["state"] not in DOCKED or s["in_cleaning"] != 0:
            raise SequenceError("Robot is not ready for a new whole-home pass")
        self.expected_mode = None
        self.status("preparing_" + mode, "Selecting " + mode + "-only mode")
        await self.command("mode", mode)
        self.expected_mode = mode
        s = self.check()  # Confirm device acknowledgement BEFORE starting.
        previous = (s.get("record") or {}).get("begin")
        requested = self.wall()
        await self.command("start", None)  # Explicit app_start; never resume a room/zone job.
        latest_start = self.wall() + 30
        deadline = self.monotonic() + 4 * 3600
        starting_deadline = self.monotonic() + 180
        seen_running = False
        self.status(mode + "ing" if mode == "vacuum" else "mopping", "Whole-home " + mode + " pass")
        while self.monotonic() < deadline:
            s = self.check()
            if s["in_cleaning"] not in (0, 1):
                raise SequenceError("Not a whole-home job; follow-up cancelled")
            if s["in_cleaning"] == 1:
                seen_running = True
            record = s.get("record")
            terminal = s["in_cleaning"] == 0 and s["state"] in DOCKED
            if seen_running and terminal and completed(record, previous, requested, self.map_id, latest_start):
                self.last_record = record
                return
            if seen_running and terminal and record and record.get("begin") != previous:
                raise SequenceError("Run ended without confirmed successful whole-home completion")
            if not seen_running and self.monotonic() >= starting_deadline:
                raise SequenceError("Cleaning did not start within three minutes")
            await self.sleep(2)
        raise SequenceError("Four-hour pass deadline reached; no automatic retry")

    async def run(self):
        original = self.ready()
        self.map_id = original["map"]
        await self.phase("vacuum")
        self.status("waiting_for_mop", "Vacuum complete; waiting for dock readiness and 30% charge")
        deadline = self.monotonic() + 4 * 3600
        while True:
            s = self.check()
            if s["in_cleaning"] != 0 or s.get("record") != self.last_record:
                raise SequenceError("Another job started or the completion record changed")
            if not s["mop_ready"]:
                raise SequenceError("Mop/water/dock needs attention; no mop pass started")
            if s["state"] in DOCKED and s["battery"] >= 30:
                break
            if self.monotonic() >= deadline:
                raise SequenceError("Dock/charge deadline reached; no mop pass started")
            await self.sleep(10)
        await self.phase("mop")
        # Restore settings only after successful completion, while still docked.
        # Failure/cancellation never starts another job or rewrites maps/schedules.
        self.expected_mode = None
        self.status("restoring", "Both passes complete; restoring previous cleaning preferences")
        self.check()
        await self.command("restore", original["preferences"])
        self.status("complete", "Whole-home vacuum and mop passes completed")
