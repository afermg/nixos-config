"""Explicit Off cooldowns and native scene context isolation; no physical IO."""
import asyncio
from datetime import timedelta
import json
import unittest
from unittest.mock import patch
import test_bilresa_lighting as base

@unittest.skipUnless(base.HELPER, 'Matching HA dependencies required')
class ManualOffRuntimeTests(unittest.IsolatedAsyncioTestCase):
    for _name in ('asyncSetUp','asyncTearDown','run_script','run_sequence','seed_ambient',
                  'bathroom_off_since','setup_priority_runtime','occupy_dark','assert_priority_state','bathroom_percent'):
        locals()[_name]=getattr(base.ButtonRuntimeTests,_name)

    def assert_paused(self, room):
        z=base.ZONES[room]
        self.assertEqual(self.hass.states.get(z['mode']).state,'Automatic')
        self.assertEqual(self.hass.states.get(z['offTimer']).state,'active')
        self.assertEqual(self.hass.states.get(z['offTimer']).attributes['duration'],'0:02:00')
        self.assertEqual(self.hass.states.get(z['active']).state,'off')

    async def test_room_slider_native_and_cycle_off_are_scoped(self):
        from homeassistant.core import Context
        from homeassistant.util import dt
        await self.setup_priority_runtime();await self.occupy_dark(*base.ZONES)
        for route,room in [('room','living_kitchen'),('slider','bathroom'),('native','living_kitchen'),('cycle','living_kitchen')]:
            with self.subTest(route=route):
                for z in base.ZONES.values():
                    await self.hass.services.async_call('timer','cancel',{'entity_id':z['offTimer']},blocking=True)
                await self.hass.async_block_till_done()
                if route=='room':await self.run_script('room_lights_power',{'room':'kitchen','power':'off'})
                elif route=='slider':await self.run_script('lighting_manual_action',{'operation':'level','room':room,'level':0})
                elif route=='native':
                    await self.hass.services.async_call('light','turn_off',{'entity_id':base.LIGHTS[2]},blocking=True,context=Context(user_id='human'))
                else:
                    for e in base.POLICY['sceneCycles'][room]:self.hass.states.async_set(e,'unknown',{'entity_id':base.ZONES[room]['lights']})
                    self.hass.states.async_set(base.POLICY['sceneCycles'][room][-1],dt.utcnow().isoformat(),{'entity_id':base.ZONES[room]['lights']})
                    await self.run_script('bilresa_cycle_scenes',{'room':room})
                await self.hass.async_block_till_done();self.assert_paused(room)
                other='bathroom' if room=='living_kitchen' else 'living_kitchen'
                self.assertEqual(self.hass.states.get(base.ZONES[other]['offTimer']).state,'idle')
                self.assert_priority_state(other)
        before={k:self.hass.states.get(z['offTimer']).as_dict() for k,z in base.ZONES.items()}
        await self.run_script('room_lights_power',{'room':'bedroom','power':'off'});await self.hass.async_block_till_done()
        self.assertEqual(before,{k:self.hass.states.get(z['offTimer']).as_dict() for k,z in base.ZONES.items()})

    async def test_deadline_repeat_stale_expiry_and_all_motion_routes(self):
        from homeassistant.util import dt
        await self.setup_priority_runtime();await self.occupy_dark(*base.ZONES)
        clock=[dt.utcnow().replace(microsecond=0)];scheduled=[]
        def track(hass, action, when):
            item=[when,action,True];scheduled.append(item)
            def cancel():item[2]=False
            return cancel
        async def advance(seconds):
            clock[0]+=timedelta(seconds=seconds)
            for item in list(scheduled):
                if item[2] and item[0]<=clock[0]:item[2]=False;item[1](clock[0])
            await self.hass.async_block_till_done()
        with patch('homeassistant.components.timer.async_track_point_in_utc_time',side_effect=track), patch('homeassistant.components.timer.dt_util.utcnow',side_effect=lambda:clock[0]):
            await self.run_script('bilresa_all_lights_off');await self.hass.async_block_till_done()
            for z in base.ZONES.values():
                self.assertEqual(dt.parse_datetime(self.hass.states.get(z['offTimer']).attributes['finishes_at']),clock[0]+timedelta(seconds=120))
            self.calls.clear();await advance(119)
            for room,z in base.ZONES.items():
                for reason in ['motion','dark','lamp','manual','schedule','startup','resume','idle','recovery']:
                    await self.run_script('lighting_manual_action',{'operation':'motion','room':room,'reason':reason})
                self.hass.states.async_set(z['motion'],'off');self.hass.states.async_set(z['illuminance'],'2')
                self.hass.states.async_set(z['motion'],'on')
            self.hass.bus.async_fire('automation_reloaded')
            await self.run_script('lighting_manual_action',{'operation':'ambient','room':'bathroom'})
            await self.hass.async_block_till_done();self.assertFalse(any(c[0]=='light' for c in self.calls))
            # Repeat at119s: the old120s deadline cannot release the new239s hold.
            await self.run_script('bilresa_all_lights_off');await self.hass.async_block_till_done()
            self.calls.clear();await advance(1)
            for room in base.ZONES:await self.run_script('lighting_manual_action',{'operation':'expire_all_off','room':room})
            await advance(118)
            for room in base.ZONES:self.assert_paused(room)
            self.assertFalse(any(c[0]=='light' for c in self.calls))
            await advance(1)
            for room in base.ZONES:self.assert_priority_state(room)

    async def test_later_manual_choices_survive_deadline(self):
        await self.setup_priority_runtime();await self.occupy_dark('living_kitchen')
        room='living_kitchen';z=base.ZONES[room]
        scene='scene.manual_mixed';self.fake_scene_definitions[scene]={base.LIGHTS[2]:{'state':'on','brightness':170},base.LIGHTS[4]:{'state':'off'}}
        self.hass.states.async_set(scene,'unknown',{'entity_id':list(self.fake_scene_definitions[scene])})
        for choice in [{'operation':'level','room':room,'level':111},{'operation':'temperature','room':room,'kelvin':4000},
                       {'operation':'room_on','room':room},{'operation':'scene','scene_entity':scene},None]:
            await self.run_script('room_lights_power',{'room':room,'power':'off'});await self.hass.async_block_till_done()
            deadline=self.hass.states.get(z['offTimer']).attributes['finishes_at']
            if choice:await self.run_script('lighting_manual_action',choice)
            else:await self.hass.services.async_call('input_select','select_option',{'entity_id':z['mode'],'option':'Manual'},blocking=True)
            await self.hass.async_block_till_done()
            self.assertEqual(self.hass.states.get(z['mode']).state,'Manual')
            self.assertEqual(self.hass.states.get(z['offTimer']).attributes['finishes_at'],deadline)
            self.calls.clear()
            await self.hass.services.async_call('timer','finish',{'entity_id':z['offTimer']},blocking=True)
            self.hass.bus.async_fire('automation_reloaded');await self.hass.async_block_till_done()
            self.assertEqual(self.hass.states.get(z['mode']).state,'Manual')
            self.assertFalse(any(c[0]=='light' for c in self.calls))

    async def test_automatic_vacancy_and_child_off_never_start_cooldown(self):
        from homeassistant.core import Context,State
        from homeassistant.util import dt
        await self.setup_priority_runtime();await self.occupy_dark(*base.ZONES)
        for room,z in base.ZONES.items():
            self.hass.states._states[z['motion']]=State(z['motion'],'off',last_changed=dt.utcnow()-timedelta(minutes=20))
            await self.run_script('lighting_manual_action',{'operation':'motion','room':room,'reason':'recovery'})
            await self.hass.services.async_call('light','turn_off',{'entity_id':z['lights']},blocking=True,context=Context(user_id='human',parent_id='wrapped-command'))
        await self.hass.async_block_till_done()
        for z in base.ZONES.values():
            self.assertEqual(self.hass.states.get(z['offTimer']).state,'idle')
            self.assertEqual(self.hass.states.get(z['offHold']).state,'off')
            self.assertTrue(all(self.hass.states.is_state(e,'off') for e in z['lights']))

    async def test_overlapping_real_scene_reproduction_and_independent_off(self):
        from homeassistant.core import Context,State
        from homeassistant.helpers.state import async_reproduce_state
        await self.setup_priority_runtime();await self.occupy_dark('living_kitchen')
        contexts=[Context(user_id='human'),Context(user_id='human')];seen=[]
        definitions={'scene.first':{base.LIGHTS[2]:{'state':'on','brightness':170},base.LIGHTS[4]:{'state':'off'}},
                     'scene.second':{base.LIGHTS[2]:{'state':'off'},base.LIGHTS[4]:{'state':'on','brightness':180}}}
        for e,members in definitions.items():self.hass.states.async_set(e,'unknown',{'entity_id':list(members)})
        async def real_reproduce(call):
            ids=call.data['entity_id'];ids=[ids] if isinstance(ids,str) else ids
            await asyncio.sleep(0) # Allow the independent human calls to overlap.
            for e in ids:
                await async_reproduce_state(self.hass,[State(lamp,v['state'],{k:x for k,x in v.items() if k!='state'}) for lamp,v in definitions[e].items()],context=call.context)
        self.hass.services.async_register('scene','turn_on',real_reproduce)
        from homeassistant.core import callback
        @callback
        def see_off(call):seen.append(call.context.id);self.fake_light(call)
        self.hass.services.async_register('light','turn_off',see_off)
        started=asyncio.Event();release=asyncio.Event()
        async def slow_manual(call):
            if call.data.get('brightness')==123:started.set();await release.wait()
            self.fake_light(call)
        self.hass.services.async_register('light','turn_on',slow_manual)
        blocked=asyncio.create_task(self.run_script('lighting_manual_action',{'operation':'level','room':'living_kitchen','level':123}))
        try:
            await asyncio.wait_for(started.wait(),5)
            await asyncio.gather(*(self.hass.services.async_call('scene','turn_on',{'entity_id':e},blocking=True,context=ctx) for e,ctx in zip(definitions,contexts)))
            for _ in range(50):
                saved=json.loads(self.hass.states.get('input_text.lighting_native_scene_contexts').state)
                if contexts[0].id in saved['ids']:break
                await asyncio.sleep(.02)
            self.assertIn(contexts[0].id,saved['ids'],'Guard recorded before shared queue unblocks')
        finally:
            release.set();await asyncio.wait_for(blocked,10)
        await self.hass.async_block_till_done()
        self.assertTrue(set(c.id for c in contexts)&set(seen),'Real HA reproduction retains human context')
        saved=json.loads(self.hass.states.get('input_text.lighting_native_scene_contexts').state)
        self.assertTrue(set(c.id for c in contexts)<=set(saved['ids']))
        z=base.ZONES['living_kitchen'];self.assertEqual(self.hass.states.get(z['mode']).state,'Manual')
        self.assertEqual(self.hass.states.get(z['offTimer']).state,'idle')
        await self.hass.services.async_call('light','turn_off',{'entity_id':base.LIGHTS[4]},blocking=True,context=Context(user_id='human'))
        await self.hass.async_block_till_done();self.assert_paused('living_kitchen')

    async def test_context_capacity_delayed_scene_same_ms_and_malformed(self):
        from homeassistant.core import Context
        await self.setup_priority_runtime()
        scene='scene.guard';self.fake_scene_definitions[scene]={base.LIGHTS[4]:{'state':'off'}}
        self.hass.states.async_set(scene,'unknown',{'entity_id':[base.LIGHTS[4]]})
        # Valid ULIDs with increasing timestamps, including more than six contexts.
        ids=['000000000'+str(i)+'0'*16 for i in range(1,9)]
        for id in ids:
            await self.hass.services.async_call('scene','turn_on',{'entity_id':scene},blocking=True,context=Context(user_id='human',id=id))
            await self.hass.async_block_till_done()
        value=self.hass.states.get('input_text.lighting_native_scene_contexts').state;guard=json.loads(value)
        self.assertLessEqual(len(value),255);self.assertEqual(guard['ids'],ids[-6:]);self.assertEqual(guard['cutoff'],ids[1][:10])
        z=base.ZONES['living_kitchen']
        for id in [ids[0],ids[1][:10]+'1'*16,'not-a-ulid']:
            await self.hass.services.async_call('light','turn_off',{'entity_id':base.LIGHTS[4]},blocking=True,context=Context(user_id='human',id=id))
            await self.hass.async_block_till_done()
            self.assertEqual(self.hass.states.get(z['offTimer']).state,'idle')
            self.assertEqual(self.hass.states.get(z['mode']).state,'Manual')
        await self.hass.services.async_call('scene','turn_on',{'entity_id':scene},blocking=True,context=Context(user_id='human',id='malformed-scene'))
        await self.hass.async_block_till_done()
        self.assertEqual(json.loads(self.hass.states.get('input_text.lighting_native_scene_contexts').state),guard)
        await self.hass.services.async_call('light','turn_off',{'entity_id':base.LIGHTS[4]},blocking=True,context=Context(user_id='human'))
        await self.hass.async_block_till_done();self.assert_paused('living_kitchen')

@unittest.skipUnless(base.HELPER, 'Matching HA dependencies required')
class NativeSceneGuardRestoreTests(unittest.IsolatedAsyncioTestCase):
    async def test_process_local_guard_starts_empty_not_restored(self):
        import copy,tempfile
        from homeassistant import loader
        from homeassistant.core import HomeAssistant,State
        from homeassistant.helpers import restore_state,area_registry,device_registry,entity_registry,floor_registry,label_registry
        from homeassistant.setup import async_setup_component
        from homeassistant.config_entries import ConfigEntries
        from homeassistant.util import dt
        with tempfile.TemporaryDirectory() as path:
            hass=HomeAssistant(path);loader.async_setup(hass);hass.config_entries=ConfigEntries(hass,{})
            try:
                device_registry.async_setup(hass)
                for registry in (floor_registry,area_registry,device_registry,entity_registry,label_registry):
                    await registry.async_load(hass,load_empty=True)
                await restore_state.async_load(hass)
                entity='input_text.lighting_native_scene_contexts'
                restore_state.async_get(hass).last_states[entity]=restore_state.StoredState(State(entity,'old-process-contexts'),None,dt.utcnow())
                self.assertTrue(await async_setup_component(hass,'input_text',{'input_text':copy.deepcopy(base.CONFIG['input_text'])}))
                await hass.async_block_till_done()
                self.assertEqual(json.loads(hass.states.get(entity).state),{'ids':[],'cutoff':''})
            finally:await hass.async_stop(force=True)

if __name__=='__main__':unittest.main()
