"""User-started sequence using HA's EXISTING Roborock coordinator and services.

No new login/client, background cleaning schedule, map edits or startup commands.
"""
import asyncio
from contextlib import suppress

import voluptuous as vol
from homeassistant.core import SupportsResponse, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers import config_validation as cv, discovery, entity_registry
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.event import async_track_state_change_event

from .sequence import Runner, SequenceError

DOMAIN = "ix_roborock_sequence"
PREFIX = "roborock_qx_revo_plus"
VACUUM = "vacuum." + PREFIX
MODE = "select." + PREFIX + "_cleaning_mode"
SIGNAL = DOMAIN + "_updated"
CONFIG_SCHEMA = vol.Schema({DOMAIN: vol.Schema({})}, extra=vol.ALLOW_EXTRA)


def number(value):
    return int(value) if value is not None else None


class Manager:
    def __init__(self, hass):
        self.hass = hass
        self.task = None
        self.runner = None
        self.context = None
        self.cancelling = False
        self.phase = "idle"
        self.message = "Ready; cleaning starts only when you press the button"
        self.bound_coordinator = None

    @callback
    def report(self, phase, message):
        self.phase, self.message = phase, message
        async_dispatcher_send(self.hass, SIGNAL)

    def coordinator(self):
        registry = entity_registry.async_get(self.hass)
        entity = registry.async_get(VACUUM)
        if entity is None or entity.platform != "roborock" or entity.disabled_by:
            raise SequenceError("Configured Roborock entity is missing or disabled")
        entry = self.hass.config_entries.async_get_entry(entity.config_entry_id)
        runtime = getattr(entry, "runtime_data", None)
        matches = [c for c in getattr(runtime, "v1", []) if c.duid_slug == entity.unique_id]
        if len(matches) != 1:
            raise SequenceError("Original Roborock integration is not ready")
        for suffix in ("cleaning_mode", "mop_intensity", "mop_mode"):
            control = registry.async_get("select." + PREFIX + "_" + suffix)
            if control is None or control.config_entry_id != entity.config_entry_id or control.device_id != entity.device_id:
                raise SequenceError("Roborock control identity mismatch")
        if self.bound_coordinator is not None and matches[0] is not self.bound_coordinator:
            raise SequenceError("Roborock integration reloaded; sequence cancelled")
        return matches[0]

    def snapshot(self):
        c = self.coordinator()
        api, state = c.properties_api, c.properties_api.status
        record = api.clean_summary.last_clean_record
        checks = {
            "binary_sensor." + PREFIX + "_mop_attached": "on",
            "binary_sensor." + PREFIX + "_water_box_attached": "on",
            "binary_sensor." + PREFIX + "_water_shortage": "off",
            "binary_sensor." + PREFIX + "_dock_dirty_water_box": "off",
            "binary_sensor." + PREFIX + "_dock_clean_water_box": "off",
            "sensor." + PREFIX + "_dock_dock_error": "ok",
        }
        robot = self.hass.states.get(VACUUM)
        return {
            "available": bool(c.last_update_success and c.data is not None and robot and robot.state != "unavailable"),
            "state": state.state_name, "in_cleaning": number(state.in_cleaning),
            "in_returning": number(state.in_returning), "error": number(state.error_code),
            "battery": state.battery or 0, "map": api.maps.current_map,
            "mode": state.current_cleaning_mode_name,
            "mop_ready": all(self.hass.states.is_state(e, v) for e, v in checks.items()),
            "record": {k: number(getattr(record, k, None)) for k in
                       ("begin", "end", "complete", "error", "clean_type", "start_type", "finish_reason", "map_flag")} if record else None,
            "preferences": {"fan_speed": state.fan_speed_name, "mop_intensity": state.water_mode_name, "mop_mode": state.mop_route_name},
        }

    async def call(self, domain, service, data):
        async with asyncio.timeout(45):
            await self.hass.services.async_call(domain, service, data, blocking=True, context=self.context)

    async def command(self, kind, value):
        if kind == "mode":
            await self.call("select", "select_option", {"entity_id": MODE, "option": value})
        elif kind == "start":
            await self.call("vacuum", "send_command", {"entity_id": VACUUM, "command": "app_start"})
        elif kind == "restore":
            for key in ("mop_intensity", "mop_mode"):
                if self.runner:
                    self.runner.check()
                if value.get(key) is not None:
                    await self.call("select", "select_option", {"entity_id": "select." + PREFIX + "_" + key, "option": value[key]})
            if self.runner:
                self.runner.check()
            if value.get("fan_speed") is not None:
                await self.call("vacuum", "set_fan_speed", {"entity_id": VACUUM, "fan_speed": value["fan_speed"]})
        else:
            raise SequenceError("Unsupported sequence command")

    @callback
    def interrupted(self, event):
        if not self.task or self.task.done() or not self.runner:
            return
        new = event.data.get("new_state")
        if new and new.entity_id == VACUUM and new.state in ("paused", "error", "unavailable"):
            self.runner.abort_reason = "Robot paused, errored or disconnected; follow-up cancelled"
        if new and new.entity_id == MODE and self.runner.expected_mode and new.state != self.runner.expected_mode:
            self.runner.abort_reason = "Cleaning mode changed externally; follow-up cancelled"

    @callback
    def manual_command(self, event):
        if not self.task or self.task.done() or event.context.id == self.context.id:
            return
        data = event.data
        targets = data.get("service_data", {}).get("entity_id", [])
        targets = [targets] if isinstance(targets, str) else targets
        if (data.get("domain") == "vacuum" and VACUUM in targets or
            data.get("domain") == "select" and any(e in targets for e in
                (MODE, "select." + PREFIX + "_mop_intensity", "select." + PREFIX + "_mop_mode", "select." + PREFIX + "_selected_map"))):
            self.runner.abort_reason = "Another robot command was requested; follow-up cancelled"

    async def start(self, call):
        if self.cancelling or self.task and not self.task.done():
            raise HomeAssistantError("A cleaning sequence is already running")
        self.context = call.context
        self.runner = Runner(self.snapshot, self.command, self.report)
        try:
            self.runner.ready()  # Read-only prerequisites, before any command.
        except SequenceError as exc:
            raise HomeAssistantError(str(exc)) from exc
        self.bound_coordinator = self.coordinator()
        self.task = self.hass.async_create_background_task(self.run(), DOMAIN, eager_start=False)

    async def run(self):
        try:
            await self.runner.run()
        except asyncio.CancelledError:
            self.report("cancelled", "Follow-up cancelled; no automatic restart")
            raise
        except Exception as exc:
            # Do not expose vendor exception payloads, credentials or whole diagnostics.
            message = str(exc) if isinstance(exc, SequenceError) else "A robot command failed; check its status. No next pass will start."
            self.report("stopped", message)
            from homeassistant.components import persistent_notification
            persistent_notification.async_create(self.hass, message, "Vacuum then mop stopped", DOMAIN)
        finally:
            self.bound_coordinator = None
            self.hass.loop.call_soon(self.report, self.phase, self.message)

    async def cancel(self, call):
        if self.cancelling or self.task is None or self.task.done():
            return  # Never stop an unrelated manual clean while the sequence is idle.
        self.cancelling = True
        try:
            self.task.cancel()
            with suppress(asyncio.CancelledError):
                await self.task
            self.context = call.context
            await self.call("vacuum", "stop", {"entity_id": VACUUM})
            await self.call("vacuum", "return_to_base", {"entity_id": VACUUM})
            self.report("cancelled", "Sequence cancelled; docking requested")
        except Exception:
            self.report("stopped", "Sequence cancelled, but docking failed; use the robot controls")
            raise
        finally:
            self.cancelling = False


async def async_setup(hass, config):
    manager = hass.data[DOMAIN] = Manager(hass)
    hass.services.async_register(DOMAIN, "start", manager.start, schema=vol.Schema({}))
    hass.services.async_register(DOMAIN, "cancel", manager.cancel, schema=vol.Schema({}))

    async def inspect(call):
        """Read-only local diagnostics; never sends a robot command."""
        return {"phase": manager.phase, "robot": manager.snapshot()}

    hass.services.async_register(DOMAIN, "inspect", inspect, schema=vol.Schema({}), supports_response=SupportsResponse.ONLY)
    async_track_state_change_event(hass, [VACUUM, MODE], manager.interrupted)
    hass.bus.async_listen("call_service", manager.manual_command)
    hass.async_create_task(discovery.async_load_platform(hass, "sensor", DOMAIN, {}, config))
    return True
