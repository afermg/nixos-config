"""Persistent modes with native HA helpers, scripts and triggers; fake hardware only."""
import copy
from datetime import timedelta
import unittest
import test_bilresa_lighting as base

@unittest.skipUnless(base.HELPER,'Matching HA dependencies required')
class ModeRuntimeTests(unittest.IsolatedAsyncioTestCase):
    # Share only fixture helpers, not the test methods of the original suite.
    for _name in ('asyncSetUp','asyncTearDown','run_script','run_sequence','seed_ambient',
                  'bathroom_off_since','setup_priority_runtime','occupy_dark','assert_priority_state','bathroom_percent'):
        locals()[_name]=getattr(base.ButtonRuntimeTests,_name)

    async def test_manual_slider_survives_motion_clock_vacancy_and_reload_until_explicit_auto(self):
        from homeassistant.core import State
        from homeassistant.util import dt
        await self.setup_priority_runtime();await self.occupy_dark('bathroom')
        z=base.ZONES['bathroom'];lamp=base.LIGHTS[5]
        slider=next(s for s in base.ROOM['template'][0]['number'] if s['default_entity_id']=='number.ix_bathroom_lighting_level')
        await self.run_sequence(slider['set_value'],{'value':80});await self.hass.async_block_till_done()
        self.assertEqual(self.hass.states.get(z['mode']).state,'Manual')
        self.assertEqual(self.hass.states.get(lamp).attributes['brightness'],204)
        self.calls.clear()
        self.hass.states._states[z['motion']]=State(z['motion'],'off',last_changed=dt.utcnow()-timedelta(minutes=20))
        for reason in ['idle','recovery','schedule','startup','manual','lamp','resume']:
            await self.run_script('lighting_manual_action',{'operation':'motion','room':'bathroom','reason':reason})
        self.hass.states.async_set(z['illuminance'],'1');self.hass.states.async_set(z['motion'],'on')
        self.hass.bus.async_fire('automation_reloaded');await self.hass.async_block_till_done()
        self.assertFalse(any(c[0]=='light' for c in self.calls))
        self.assertEqual(self.hass.states.get(lamp).attributes['brightness'],204)
        await self.run_script('lighting_toggle_automatic',{'room':'bathroom'});await self.hass.async_block_till_done()
        self.assertEqual(self.hass.states.get(z['mode']).state,'Automatic');self.assert_priority_state('bathroom')

    async def test_all_off_rearms_both_zones_with_two_minute_timers(self):
        await self.setup_priority_runtime();await self.occupy_dark(*base.ZONES)
        for room in base.ZONES:
            await self.run_script('lighting_manual_action',{'operation':'level','room':room,'level':204})
        for _ in range(2):await self.run_script('bilresa_all_lights_off')
        await self.hass.async_block_till_done()
        for z in base.ZONES.values():
            self.assertEqual(self.hass.states.get(z['mode']).state,'Automatic')
            self.assertEqual(self.hass.states.get(z['offTimer']).attributes['duration'],'0:02:00')
            self.assertTrue(all(self.hass.states.is_state(e,'off') for e in z['lights']))
        await self.hass.services.async_call('timer','finish',{'entity_id':[z['offTimer'] for z in base.ZONES.values()]},blocking=True)
        await self.hass.async_block_till_done()
        for room in base.ZONES:self.assert_priority_state(room)
        self.assertTrue(all(self.hass.states.get(e).attributes['brightness']==204 for e in base.ZONES['living_kitchen']['lights']))

    async def test_manual_input_after_all_off_is_not_undone_by_expiry_or_reload(self):
        await self.setup_priority_runtime();await self.occupy_dark(*base.ZONES)
        for room,z in base.ZONES.items():
            with self.subTest(room=room):
                await self.run_script('bilresa_all_lights_off');await self.hass.async_block_till_done()
                await self.run_script('lighting_manual_action',{'operation':'level','room':room,'level':123})
                await self.hass.services.async_call('timer','finish',{'entity_id':z['offTimer']},blocking=True)
                self.hass.bus.async_fire('automation_reloaded');await self.hass.async_block_till_done()
                self.assertEqual(self.hass.states.get(z['mode']).state,'Manual')
                self.assertTrue(all(self.hass.states.get(e).attributes['brightness']==123 for e in z['lights']))

    async def test_native_app_all_off_uses_same_both_zone_rearm_path(self):
        from homeassistant.core import Context
        await self.setup_priority_runtime();await self.occupy_dark(*base.ZONES)
        for room in base.ZONES:
            await self.run_script('lighting_manual_action',{'operation':'level','room':room,'level':123})
        await self.hass.services.async_call('light','turn_off',{'entity_id':base.LIGHTS},blocking=True,context=Context(user_id='human'))
        await self.hass.async_block_till_done()
        for z in base.ZONES.values():
            self.assertEqual(self.hass.states.get(z['mode']).state,'Automatic')
            self.assertEqual(self.hass.states.get(z['offTimer']).state,'active')
        self.assertTrue(all(self.hass.states.is_state(e,'off') for e in base.LIGHTS))
        for room,z in base.ZONES.items():
            await self.hass.services.async_call('timer','finish',{'entity_id':z['offTimer']},blocking=True)
            await self.hass.async_block_till_done();self.assert_priority_state(room)

    async def test_automatic_profile_with_human_parent_context_never_latches_manual(self):
        from homeassistant.core import Context
        await self.setup_priority_runtime();await self.occupy_dark('bathroom')
        z=base.ZONES['bathroom'];self.calls.clear()
        await self.hass.services.async_call('light','turn_on',{'entity_id':base.LIGHTS[5],'brightness_pct':self.bathroom_percent},
            blocking=True,context=Context(user_id='human',parent_id='automatic-script'))
        await self.hass.async_block_till_done()
        self.assertEqual(self.hass.states.get(z['mode']).state,'Automatic')
        await self.hass.services.async_call('light','turn_on',{'entity_id':base.LIGHTS[5],'brightness':170},
            blocking=True,context=Context(user_id='human'))
        await self.hass.async_block_till_done()
        self.assertEqual(self.hass.states.get(z['mode']).state,'Manual')
        self.assertEqual(self.hass.states.get(base.LIGHTS[5]).attributes['brightness'],170)

    async def test_manual_command_queued_behind_inflight_automatic_wins(self):
        import asyncio
        await self.setup_priority_runtime();z=base.ZONES['bathroom']
        started=asyncio.Event();release=asyncio.Event()
        async def slow_on(call):
            if 'brightness_pct' in call.data:started.set();await release.wait()
            self.fake_light(call)
        self.hass.services.async_register('light','turn_on',slow_on)
        self.hass.states.async_set(z['illuminance'],'1');self.hass.states.async_set(z['motion'],'on')
        task=None
        try:
            await asyncio.wait_for(started.wait(),5)
            task=asyncio.create_task(self.run_script('lighting_manual_action',{'operation':'level','room':'bathroom','level':180}))
            await asyncio.sleep(0);release.set();await asyncio.wait_for(task,10)
            await self.hass.async_block_till_done()
            self.assertEqual(self.hass.states.get(z['mode']).state,'Manual')
            self.assertEqual(self.hass.states.get(base.LIGHTS[5]).attributes['brightness'],180)
        finally:
            release.set()
            if task and not task.done():task.cancel()
            if task:await asyncio.gather(task,return_exceptions=True)

    async def test_unknown_mode_fails_closed_for_on_and_off(self):
        await self.setup_priority_runtime();await self.occupy_dark('bathroom')
        z=base.ZONES['bathroom']
        for mode in ['unknown','unavailable']:
            self.hass.states.async_set(z['mode'],mode);self.calls.clear()
            for reason in ['motion','idle','schedule','recovery','startup']:
                await self.run_script('lighting_manual_action',{'operation':'motion','room':'bathroom','reason':reason})
            await self.hass.async_block_till_done();self.assertFalse(any(c[0]=='light' for c in self.calls))

@unittest.skipUnless(base.HELPER,'Matching HA dependencies required')
class ModeRestoreTests(unittest.IsolatedAsyncioTestCase):
    async def test_native_input_select_restores_manual_and_new_helpers_default_automatic(self):
        import tempfile
        from homeassistant import loader
        from homeassistant.core import HomeAssistant,State
        from homeassistant.helpers import restore_state,area_registry,device_registry,entity_registry,floor_registry,label_registry
        from homeassistant.setup import async_setup_component
        from homeassistant.config_entries import ConfigEntries
        for restored in [None,'Manual','Automatic']:
            with tempfile.TemporaryDirectory() as path:
                hass=HomeAssistant(path);loader.async_setup(hass);hass.config_entries=ConfigEntries(hass,{})
                try:
                    device_registry.async_setup(hass)
                    for registry in (floor_registry,area_registry,device_registry,entity_registry,label_registry):
                        await registry.async_load(hass,load_empty=True)
                    await restore_state.async_load(hass)
                    if restored:
                        from homeassistant.util import dt
                        data=restore_state.async_get(hass)
                        for z in base.ZONES.values():
                            data.last_states[z['mode']]=restore_state.StoredState(State(z['mode'],restored),None,dt.utcnow())
                    self.assertTrue(await async_setup_component(hass,'input_select',{'input_select':copy.deepcopy(base.CONFIG['input_select'])}))
                    await hass.async_block_till_done()
                    for z in base.ZONES.values():self.assertEqual(hass.states.get(z['mode']).state,restored or 'Automatic')
                finally:await hass.async_stop(force=True)

if __name__=='__main__':unittest.main()
