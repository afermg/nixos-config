"""Validate the evaluated Nix automation and, optionally, HA's real conditions.

On ix, run with IX_HA_DEPENDENCY_HELPER pointing to the existing dependency
loader to enable the in-memory HA tests. These never connect to the live API.
"""
import copy
from datetime import timedelta
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest


MODULE = Path(__file__).resolve().parents[1] / "motion-lighting.nix"
CONFIG = json.loads(subprocess.check_output([
    "nix", "eval", "--impure", "--json", "--expr",
    f"(import {MODULE} {{}}).services.home-assistant.config",
], text=True))
AUTOMATION = CONFIG["automation myggspray"][0]
CHOICES = AUTOMATION["actions"][0]["choose"]
MOTION = "binary_sensor.myggspray_wrlss_mtn_sensor_occupancy"
LUX = "sensor.myggspray_wrlss_mtn_sensor_illuminance"
ACTIVE = "input_boolean.myggspray_lighting_active"
LIGHTS = [
    "light.kajplats_e26_ws_globe_1600lm",
    "light.living_room_kajplats_e26_living_room_1100lm",
    "light.kitchen_kajplats_e26_kitchen_1100lm",
]


class MotionPolicyTests(unittest.TestCase):
    def test_module_is_imported(self):
        self.assertIn('./motion-lighting.nix', (MODULE.parent / 'services.nix').read_text())

    def test_targets_only_the_three_named_lights(self):
        on = CHOICES[0]["sequence"][1]
        off = CHOICES[1]["sequence"][0]
        self.assertEqual(on["action"], "light.turn_on")
        self.assertEqual(off["action"], "light.turn_off")
        self.assertEqual(on["target"]["entity_id"], LIGHTS)
        self.assertEqual(off["target"]["entity_id"], LIGHTS)
        self.assertNotIn("data", on)  # No forced brightness/color change.

    def test_darkness_is_required_only_to_activate(self):
        checks = CHOICES[0]["conditions"]
        self.assertIn({"condition": "numeric_state", "entity_id": LUX, "below": 50}, checks)
        self.assertIn({"condition": "state", "entity_id": MOTION, "state": "on"}, checks)
        self.assertNotIn(LUX, json.dumps(AUTOMATION["conditions"]))
        self.assertIn("lighting_manual_living_kitchen", json.dumps(AUTOMATION["conditions"]))
        self.assertNotIn("lighting_manual_override",json.dumps(AUTOMATION["conditions"]))
        self.assertTrue(AUTOMATION['initial_state'])
        self.assertNotIn(LUX, json.dumps(CHOICES[1]))

    def test_continuously_clear_for_ten_minutes(self):
        idle = next(t for t in AUTOMATION["triggers"] if t["id"] == "idle")
        self.assertEqual(idle, {"trigger": "state", "entity_id": MOTION,
                                "to": "off", "for": {"minutes": 10}, "id": "idle"})
        self.assertIn({"condition": "state", "entity_id": MOTION, "state": "off"},
                      CHOICES[1]["conditions"])
        self.assertIn(">= 600", CHOICES[1]["conditions"][2]["value_template"])

    def test_only_automatically_claimed_lights_are_turned_off(self):
        self.assertIn({"condition": "state", "entity_id": ACTIVE, "state": "on"},
                      CHOICES[1]["conditions"])
        self.assertEqual(CHOICES[0]["sequence"][0]["action"], "input_boolean.turn_on")
        self.assertEqual(CHOICES[1]["sequence"][1]["action"], "input_boolean.turn_off")
        self.assertNotIn("initial", CONFIG["input_boolean"]["myggspray_lighting_active"])

    def test_darkening_an_occupied_room_is_supported(self):
        dark = next(t for t in AUTOMATION["triggers"] if t["id"] == "dark")
        self.assertEqual(dark, {"trigger": "numeric_state", "entity_id": LUX,
                                "below": 50, "id": "dark"})

    def test_restart_recovery_does_not_turn_on_manual_lights(self):
        recovery = next(t for t in AUTOMATION["triggers"] if t["id"] == "recovery")
        self.assertEqual(recovery, {"trigger": "time_pattern", "minutes": "/1", "id": "recovery"})
        self.assertNotIn("recovery", CHOICES[0]["conditions"][0]["id"])
        self.assertIn("startup", CHOICES[0]["conditions"][0]["id"])

    def test_actions_are_serialized_without_a_long_running_delay(self):
        self.assertEqual(AUTOMATION["mode"], "queued")
        self.assertEqual(AUTOMATION["max"], 5)
        self.assertNotIn('"delay"', json.dumps(AUTOMATION))
        self.assertNotIn('"wait_for_trigger"', json.dumps(AUTOMATION))


BATHROOM = CONFIG["automation myggspray"][1]
BATH_MOTION = MOTION + "_2"
BATH_LUX = LUX + "_2"
BATH_ACTIVE = "input_boolean.myggspray_bathroom_lighting_active"
BATH_LIGHT = "light.bathroom_kajplats_e26_1100lm_bathroom_2"


class BathroomMotionPolicyTests(unittest.TestCase):
    def test_bathroom_has_its_own_sensor_and_ownership(self):
        choices = BATHROOM["actions"][0]["choose"]
        self.assertEqual(BATHROOM["triggers"][0]["entity_id"], BATH_MOTION)
        self.assertEqual(BATHROOM["triggers"][1]["entity_id"], BATH_LUX)
        self.assertEqual(choices[0]["sequence"][0]["target"]["entity_id"], BATH_ACTIVE)
        self.assertEqual(choices[1]["sequence"][1]["target"]["entity_id"], BATH_ACTIVE)
        self.assertNotIn("initial", CONFIG["input_boolean"]["myggspray_bathroom_lighting_active"])

    def test_dim_warm_bathroom_only_and_five_minute_timeout(self):
        choices = BATHROOM["actions"][0]["choose"]
        on = choices[0]["sequence"][1]
        self.assertEqual(on["target"]["entity_id"], [BATH_LIGHT])
        self.assertEqual(on["data"], {"brightness_pct": 10, "color_temp_kelvin": 2700})
        self.assertEqual(choices[1]["sequence"][0]["target"]["entity_id"], [BATH_LIGHT])
        self.assertEqual(BATHROOM["triggers"][2]["for"], {"minutes": 5})
        self.assertIn(">= 300", choices[1]["conditions"][2]["value_template"])
        self.assertNotIn(BATH_LUX, json.dumps(choices[1]))

    def test_manual_bathroom_lighting_is_not_dimmed_or_claimed(self):
        checks = BATHROOM["actions"][0]["choose"][0]["conditions"]
        self.assertIn({"condition": "state", "entity_id": [BATH_LIGHT], "state": "off"}, checks)


HELPER = os.environ.get("IX_HA_DEPENDENCY_HELPER")
if HELPER:
    runpy.run_path(HELPER)["load_ha_dependencies"]()


@unittest.skipUnless(HELPER, "HA runtime condition tests require ix's installed HA dependencies")
class HomeAssistantConditionTests(unittest.IsolatedAsyncioTestCase):
    async def check_cases(self, automation, motion_entity, lux_entity, active_entity, cases):
        from homeassistant.components.automation.config import PLATFORM_SCHEMA
        from homeassistant.core import HomeAssistant, State
        from homeassistant.exceptions import ConditionError
        from homeassistant.helpers import condition, config_validation as cv
        from homeassistant.util import dt

        with tempfile.TemporaryDirectory(prefix="myggspray-test-") as directory:
            hass = HomeAssistant(directory)
            groups = []
            try:
                validated = await cv.async_validate(
                    hass, PLATFORM_SCHEMA, copy.deepcopy(automation)
                )
                for choice in validated["actions"][0]["choose"]:
                    groups.append([await condition.async_from_config(hass, c)
                                   for c in choice["conditions"]])
                for trigger, motion, lux, owned, seconds, light, expected in cases:
                    with self.subTest(trigger=trigger, motion=motion, lux=lux,
                                      owned=owned, seconds=seconds):
                        # This is a disposable in-memory HA instance, NOT live state.
                        hass.states._states[motion_entity] = State(
                            motion_entity, motion, last_changed=dt.utcnow() - timedelta(seconds=seconds)
                        )
                        hass.states.async_set(lux_entity, lux)
                        hass.states.async_set(active_entity, owned)
                        hass.states.async_set(BATH_LIGHT, light)
                        selected = None
                        for index, checks in enumerate(groups):
                            try:
                                matched = all(c.async_check(variables={"trigger": {"id": trigger}})
                                              for c in checks)
                            except ConditionError:
                                matched = False
                            if matched:
                                selected = index
                                break
                        self.assertEqual(selected, expected)
            finally:
                for checks in groups:
                    for c in checks:
                        c.async_unload()
                await hass.async_stop(force=True)

    async def test_actual_ha_living_kitchen_condition_matrix(self):
        # trigger, motion, lux, owned, clear seconds, bulb state, expected branch
        cases = [
            ("motion", "on", "49", "off", 0, "off", 0),
            ("motion", "on", "50", "off", 0, "off", None),
            ("motion", "on", "100", "off", 0, "off", None),
            ("motion", "on", "unknown", "off", 0, "off", None),
            ("motion", "on", "unavailable", "off", 0, "off", None),
            ("dark", "on", "1", "off", 0, "off", 0),
            ("dark", "off", "1", "off", 700, "off", None),
            ("idle", "off", "200", "on", 601, "on", 1),
            ("idle", "off", "unknown", "on", 601, "on", 1),
            ("recovery", "off", "1", "on", 599, "on", None),
            ("recovery", "off", "1", "on", 601, "on", 1),
            ("recovery", "off", "1", "off", 601, "on", None),
            ("motion", "on", "200", "on", 0, "on", None),
            ("idle", "on", "1", "on", 700, "on", None),
            ("recovery", "unavailable", "1", "on", 700, "on", None),
            ("recovery", "unknown", "1", "on", 700, "on", None),
            ("startup", "on", "1", "on", 0, "off", 0),
            ("startup", "off", "1", "on", 0, "on", None),
            ("recovery", "on", "1", "off", 0, "off", None),
        ]
        await self.check_cases(AUTOMATION, MOTION, LUX, ACTIVE, cases)

    async def test_actual_ha_bathroom_condition_matrix(self):
        cases = [
            ("motion", "on", "49", "off", 0, "off", 0),
            ("motion", "on", "50", "off", 0, "off", None),
            ("motion", "on", "unknown", "off", 0, "off", None),
            ("motion", "on", "1", "off", 0, "on", None),
            ("motion", "on", "1", "on", 0, "on", None),
            ("motion", "on", "1", "off", 0, "unavailable", None),
            ("dark", "on", "1", "off", 0, "off", 0),
            ("dark", "off", "1", "off", 400, "off", None),
            ("idle", "off", "200", "on", 301, "on", 1),
            ("idle", "off", "unknown", "on", 301, "on", 1),
            ("recovery", "off", "1", "on", 299, "on", None),
            ("recovery", "off", "1", "on", 301, "on", 1),
            ("recovery", "off", "1", "off", 301, "on", None),
            ("idle", "on", "1", "on", 400, "on", None),
            ("recovery", "unavailable", "1", "on", 400, "on", None),
            ("recovery", "unknown", "1", "on", 400, "on", None),
            ("startup", "on", "1", "off", 0, "off", 0),
            ("startup", "on", "1", "off", 0, "on", None),
            ("startup", "off", "1", "on", 0, "on", None),
        ]
        await self.check_cases(BATHROOM, BATH_MOTION, BATH_LUX, BATH_ACTIVE, cases)


if __name__ == "__main__":
    unittest.main()
