"""Lighting policies and actual HA templates/scripts with fake hardware services."""
import copy
from datetime import timedelta
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
def evaluate(name, args='{}'):
    return json.loads(subprocess.check_output(['nix', 'eval', '--impure', '--json', '--expr',
        f'(import {ROOT / name} {args}).services.home-assistant.config'], text=True))
CONFIG = evaluate('bilresa-lighting.nix')
ROOM = evaluate('room-lighting.nix', '{pkgs.writeText = name: text: text;}')
MOTION_CONFIG = evaluate('motion-lighting.nix')
SCRIPTS = CONFIG['script'] | ROOM['script'] | MOTION_CONFIG['script']
AUTOMATION, NATIVE_SCENE, NATIVE_LIGHT = CONFIG['automation bilresa']
POLICY = json.loads(subprocess.check_output(['nix','eval','--impure','--json','--expr',
    f'import {ROOT / "lighting-policy.nix"}'],text=True))
ZONES = POLICY['motionZones']
LIGHTS = json.loads(subprocess.check_output(['nix','eval','--impure','--json','--expr',
    f'(import {ROOT / "lighting-policy.nix"}).lights'], text=True))

class ButtonPolicyTests(unittest.TestCase):
    def test_both_registered_buttons_and_no_startup_trigger(self):
        self.assertEqual(AUTOMATION['triggers'][0]['entity_id'], [
            'event.bedroom_bilresa_dual_button_1_button_1', 'event.bilresa_dual_button_button_1'])
        self.assertEqual(AUTOMATION['triggers'][1]['entity_id'], [
            'event.bedroom_bilresa_dual_button_1_button_2', 'event.bilresa_dual_button_button_2'])
        self.assertTrue(all(t['trigger']=='state' for t in AUTOMATION['triggers']))
    def test_only_six_individual_lamps_and_serialized_actions(self):
        self.assertEqual(len(set(LIGHTS)), 6)
        self.assertTrue(all(x.startswith('light.') for x in LIGHTS))
        self.assertNotIn('switch.turn_', json.dumps(CONFIG))
        self.assertEqual(SCRIPTS['lighting_manual_action']['mode'], 'queued')
        for name in ('bilresa_all_lights_off','bilresa_adjust_lights','lighting_activate_scene',
                     'lighting_resume_automatic','room_lights_power','room_lights_proportional'):
            self.assertEqual(SCRIPTS[name]['sequence'][-1]['action'], 'script.lighting_manual_action')
    def test_manual_ownership_is_persistent_without_disabling_motion(self):
        for zone in ZONES.values():self.assertNotIn('initial',CONFIG['input_boolean'][zone['manual'].split('.')[1]])
        seq=SCRIPTS['lighting_take_manual_control']['sequence']
        for step,zone in zip(seq[1:],ZONES.values()):
            actions=step['choose'][0]['sequence']
            self.assertEqual([x['action'] for x in actions],['input_boolean.turn_on','input_boolean.turn_off'])
            self.assertEqual(actions[1]['target']['entity_id'],zone['active'])
        self.assertNotIn('automation.turn_off',json.dumps(SCRIPTS))
        self.assertTrue(AUTOMATION['initial_state'])
    def test_editable_scene_cycle_is_restricted(self):
        text=SCRIPTS['bilresa_cycle_scenes']['sequence'][1]['variables']['scene_ids']
        self.assertIn("label_entities('Button scenes')", text)
        self.assertIn("reject('in', allowed)", text)
        self.assertIn("attributes.entity_id", text)

HELPER=os.environ.get('IX_HA_DEPENDENCY_HELPER')
if HELPER:runpy.run_path(HELPER)['load_ha_dependencies']()

@unittest.skipUnless(HELPER,'Requires matching HA dependencies; no live services used')
class ButtonRuntimeTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        from homeassistant.core import HomeAssistant,callback
        from homeassistant.helpers import config_validation as cv
        from homeassistant.helpers.script import Script
        import logging
        self.script_errors=[]
        class ScriptErrors(logging.Handler):
            def emit(handler,record):
                text=record.getMessage()
                if record.levelno>=logging.ERROR or 'Maximum number of runs' in text:
                    self.script_errors.append(text)
        self.error_handler=ScriptErrors();logging.getLogger('homeassistant.helpers.script').addHandler(self.error_handler)
        self.directory=tempfile.TemporaryDirectory(prefix='lighting-test-')
        self.hass=HomeAssistant(self.directory.name);self.calls=[];self.scripts={}
        from homeassistant.helpers import area_registry,device_registry,entity_registry,label_registry,floor_registry
        device_registry.async_setup(self.hass)
        for registry in (floor_registry,area_registry,device_registry,entity_registry,label_registry):
            await registry.async_load(self.hass,load_empty=True)
        @callback
        def record(call):
            self.calls.append((call.domain,call.service,dict(call.data)))
            ids=call.data.get('entity_id',[])
            if isinstance(ids,str):ids=[ids]
            if call.domain in ('input_boolean','automation'):
                for entity in ids:self.hass.states.async_set(entity,'on' if call.service=='turn_on' else 'off')
        for domain,service in [('light','turn_on'),('light','turn_off'),('scene','turn_on'),
                ('automation','turn_off'),('automation','turn_on'),('input_boolean','turn_off'),('input_boolean','turn_on')]:
            self.hass.services.async_register(domain,service,record)
        for name,config in SCRIPTS.items():
            seq=await cv.async_validate(self.hass,cv.SCRIPT_SCHEMA,copy.deepcopy(config['sequence']))
            self.scripts[name]=Script(self.hass,seq,name,'script',script_mode='queued',max_runs=20)
        for name in self.scripts:
            async def invoke(call, name=name):
                await self.scripts[name].async_run(dict(call.data),call.context)
            self.hass.services.async_register('script',name,invoke)
        for entity in LIGHTS:self.hass.states.async_set(entity,'off',{'brightness':50})
        self.hass.states.async_set('input_boolean.lighting_manual_override','off')
        for zone in ZONES.values():
            self.hass.states.async_set(zone['manual'],'off')
            self.hass.states.async_set(zone['automation'],'on')
            self.hass.states.async_set(zone['motion'],'off')
            self.hass.states.async_set(zone['illuminance'],'100')
    async def asyncTearDown(self):
        for unsub in getattr(self,'trigger_unsubs',[]):unsub()
        for check in getattr(self,'trigger_checks',[]):check.async_unload()
        for script in self.scripts.values():await script.async_stop()
        await self.hass.async_stop(force=True);self.directory.cleanup()
        import logging
        logging.getLogger('homeassistant.helpers.script').removeHandler(self.error_handler)
        self.assertEqual(self.script_errors,[])
    async def run_script(self,name,variables=None):
        from homeassistant.core import Context
        await self.scripts[name].async_run(variables or {},Context())
    async def run_sequence(self,sequence,variables):
        from homeassistant.core import Context
        from homeassistant.helpers import config_validation as cv
        from homeassistant.helpers.script import Script
        s=Script(self.hass,await cv.async_validate(self.hass,cv.SCRIPT_SCHEMA,copy.deepcopy(sequence)),
                 'mapping','script',script_mode='queued')
        try:await s.async_run(variables,Context())
        finally:await s.async_stop()
    async def test_brightness_common_gain_and_preserved_off_colors(self):
        for first,second,scale,expected in [(200,100,.8,[160,80]),(200,100,1.25,[250,125]),
                (240,120,1.25,[255,128]),(255,100,1.25,[255,100]),(2,1,.8,[2,1])]:
            self.calls.clear()
            self.hass.states.async_set(LIGHTS[0],'on',{'brightness':first,'color_temp_kelvin':2700})
            self.hass.states.async_set(LIGHTS[1],'on',{'brightness':second})
            self.hass.states.async_set('switch.critical_plug','on',{'brightness':255})
            await self.run_script('bilresa_adjust_lights',{'scale':scale})
            commands=[c for c in self.calls if c[0]=='light']
            self.assertEqual({c[2]['entity_id'][0] if isinstance(c[2]['entity_id'],list) else c[2]['entity_id']:c[2]['brightness'] for c in commands},dict(zip(LIGHTS[:2],expected)))
            self.assertTrue(all(set(c[2])=={'entity_id','brightness'} for c in commands))
            self.assertTrue(all(c[0]=='light' for c in self.calls))
    async def test_scene_validation_precedes_pause(self):
        for entity,members in [('scene.safe',[LIGHTS[0]]),('scene.plug',[LIGHTS[0],'switch.critical_plug']),
                              ('scene.unknown_light',['light.not_allowlisted']),('scene.empty',[])]:
            self.hass.states.async_set(entity,'unknown',{'entity_id':members})
            self.calls.clear();await self.run_script('lighting_activate_scene',{'scene_entity':entity})
            if entity=='scene.safe':
                self.assertEqual(self.calls[-1][:2],('scene','turn_on'))
                self.assertEqual(len(self.calls),1) # Bedroom cannot pause either sensor.
            else:self.assertEqual(self.calls,[])
        self.hass.states.async_set(LIGHTS[0],'on',{'entity_id':['switch.critical_plug']})
        self.calls.clear();await self.run_script('lighting_activate_scene',{'scene_entity':'scene.safe'})
        self.assertEqual(self.calls,[])
    async def test_all_off_then_resume_and_invalid_inputs(self):
        await self.run_script('bilresa_all_lights_off')
        self.assertEqual(self.calls[-1],('light','turn_off',{'entity_id':LIGHTS}))
        for zone in ZONES.values():
            self.assertEqual(self.hass.states.get(zone['manual']).state,'on')
            self.assertEqual(self.hass.states.get(zone['automation']).state,'on')
        self.calls.clear();events=[]
        self.hass.bus.async_listen('ix_resume_automatic_lighting',lambda event:events.append(event))
        await self.run_script('lighting_resume_automatic');await self.hass.async_block_till_done()
        self.assertEqual([x[:2] for x in self.calls],[('input_boolean','turn_off')]+[('input_boolean','turn_off'),('automation','turn_on')]*2)
        self.assertEqual({event.data['room'] for event in events},set(ZONES))
        for variables in ({'operation':'bad'},{'operation':'brightness','scale':0},
                          {'operation':'brightness','scale':'invalid'},{'operation':'room_off','room':'bad'},
                          {'operation':'level','level':-1},{'operation':'level','level':256},
                          {'operation':'takeover','affected_lights':['switch.plug']}):
            self.calls.clear();await self.run_script('lighting_manual_action',variables);self.assertEqual(self.calls,[])
    async def test_room_filter_never_includes_plugs_or_extra_lights(self):
        from homeassistant.helpers import area_registry,device_registry,entity_registry
        ar=area_registry.async_get(self.hass);area=ar.async_create('Bedroom')
        er=entity_registry.async_get(self.hass)
        for entity in [LIGHTS[0],'light.not_allowlisted','switch.critical_plug']:
            domain,name=entity.split('.',1)
            self.hass.states.async_remove(entity)
            entry=er.async_get_or_create(domain,'test',name,suggested_object_id=name)
            self.assertEqual(entry.entity_id,entity)
            er.async_update_entity(entry.entity_id,area_id=area.id)
            self.hass.states.async_set(entity,'on',{'brightness':100})
        self.calls.clear();await self.run_script('room_lights_power',{'room':'bedroom','power':'off'})
        self.assertEqual(self.calls[-1],('light','turn_off',{'entity_id':[LIGHTS[0]]}))
    async def test_combined_room_uses_both_areas_and_one_brightness_gain(self):
        from homeassistant.helpers import area_registry,entity_registry
        ar=area_registry.async_get(self.hass)
        areas={name:ar.async_create(label) for name,label in [('bedroom','Bedroom'),
            ('living_room','Living room'),('kitchen','Kitchen'),('bathroom','Bathroom')]}
        er=entity_registry.async_get(self.hass)
        membership=dict(zip(LIGHTS,['bedroom','bedroom','living_room','living_room','kitchen','bathroom']))
        membership.update({'switch.critical_plug':'living_room','light.not_allowlisted':'kitchen'})
        levels=dict(zip(LIGHTS[2:5],[240,120,60]))
        for entity,area in membership.items():
            domain,name=entity.split('.',1);self.hass.states.async_remove(entity)
            entry=er.async_get_or_create(domain,'test',name,suggested_object_id=name)
            self.assertEqual(entry.entity_id,entity)
            er.async_update_entity(entity,area_id=areas[area].id)
            self.hass.states.async_set(entity,'on',{'brightness':levels.get(entity,100),'color_temp_kelvin':2700})
        for power in ['on','off']:
            self.calls.clear();await self.run_script('room_lights_power',{'room':'living_kitchen','power':power})
            self.assertEqual([c for c in self.calls if c[0]=='light'],
                             [('light','turn_'+power,{'entity_id':LIGHTS[2:5]})])
            for c in self.calls:
                if c[0]=='automation':self.assertEqual(c[2]['entity_id'],[ZONES['living_kitchen']['automation']])
            self.assertEqual(self.hass.states.get(ZONES['bathroom']['manual']).state,'off')
        for scale,expected in [(1.25,[255,128,64]),(.8,[192,96,48])]:
            self.calls.clear();await self.run_script('room_lights_proportional',{'room':'living_kitchen','scale':scale})
            commands=[c for c in self.calls if c[0]=='light']
            actual={c[2]['entity_id'][0] if isinstance(c[2]['entity_id'],list) else c[2]['entity_id']:c[2]['brightness'] for c in commands}
            self.assertEqual(actual,dict(zip(LIGHTS[2:5],expected)))
            self.assertTrue(all(set(c[2])=={'entity_id','brightness'} for c in commands))
        self.hass.states.async_set(LIGHTS[4],'off',{'brightness':60})
        self.calls.clear();await self.run_script('room_lights_proportional',{'room':'living_kitchen','scale':.8})
        self.assertEqual(len([c for c in self.calls if c[0]=='light']),2)
        # Cached/custom callers can still target the individual areas, unchanged.
        for room,expected in [('living_room',LIGHTS[2:4]),('kitchen',LIGHTS[4:5])]:
            self.calls.clear();await self.run_script('room_lights_power',{'room':room,'power':'off'})
            self.assertEqual(self.calls[-1],('light','turn_off',{'entity_id':expected}))
        self.assertEqual({e:er.async_get(e).area_id for e in membership},
                         {e:areas[area].id for e,area in membership.items()})
    async def test_cycle_wraps_skips_unsafe_and_ignores_missing_label(self):
        from homeassistant.helpers import label_registry,entity_registry
        from homeassistant.util import dt
        labels=label_registry.async_get(self.hass);label=labels.async_create('Button scenes')
        registry=entity_registry.async_get(self.hass)
        for name,members in [('a',[LIGHTS[0]]),('b',[LIGHTS[1]]),('c',[LIGHTS[2]]),('unsafe',['switch.critical_plug'])]:
            entry=registry.async_get_or_create('scene','test',name,suggested_object_id=name)
            registry.async_update_entity(entry.entity_id,labels={label.label_id})
            self.hass.states.async_set(entry.entity_id,'unknown',{'entity_id':members})
        for direction,latest,expected in [
                (None,None,'scene.a'),('next',None,'scene.a'),('previous',None,'scene.c'),
                ('next','scene.a','scene.b'),('previous','scene.a','scene.c'),
                ('next','scene.b','scene.c'),('previous','scene.b','scene.a'),
                ('next','scene.c','scene.a'),('previous','scene.c','scene.b')]:
            for entity in ['scene.a','scene.b','scene.c']:
                self.hass.states.async_set(entity,'unknown',{'entity_id':[LIGHTS[0]]})
            if latest:self.hass.states.async_set(latest,dt.utcnow().isoformat(),{'entity_id':[LIGHTS[0]]})
            self.calls.clear()
            await self.run_script('bilresa_cycle_scenes',{} if direction is None else {'direction':direction})
            self.assertEqual(self.calls[-1],('scene','turn_on',{'entity_id':[expected]}))
            self.assertEqual(len(self.calls),1) # These scene fixtures contain bedroom lamps only.
        for invalid in ['backwards','',0]:
            self.calls.clear();await self.run_script('bilresa_cycle_scenes',{'direction':invalid});self.assertEqual(self.calls,[])
        # One candidate wraps to itself in both directions; unsafe members stay excluded.
        for entity in ['scene.b','scene.c']:registry.async_update_entity(entity,labels=set())
        for direction in ['next','previous']:
            self.calls.clear();await self.run_script('bilresa_cycle_scenes',{'direction':direction})
            self.assertEqual(self.calls[-1],('scene','turn_on',{'entity_id':['scene.a']}))
        # No safe candidates: don't pause motion or invoke a scene.
        registry.async_update_entity('scene.a',labels=set())
        for direction in ['next','previous']:
            self.calls.clear();await self.run_script('bilresa_cycle_scenes',{'direction':direction});self.assertEqual(self.calls,[])
        labels.async_delete(label.label_id)
        self.calls.clear();await self.run_script('bilresa_cycle_scenes');self.assertEqual(self.calls,[])
    async def test_event_filter_and_all_six_mappings(self):
        from homeassistant.components.automation.config import PLATFORM_SCHEMA
        from homeassistant.core import State
        from homeassistant.helpers import condition,config_validation as cv
        from homeassistant.util import dt
        config=await cv.async_validate(self.hass,PLATFORM_SCHEMA,copy.deepcopy(AUTOMATION))
        check=await condition.async_from_config(self.hass,config['conditions'][0])
        try:
            for side,event,previous,age,restored,accepted in [
                ('top','multi_press_1','unknown',0,False,True),('bottom','multi_press_1','unknown',0,False,True),
                ('top','long_press','unknown',0,False,True),('bottom','long_press','unknown',0,False,True),
                ('top','multi_press_2','unknown',0,False,True),('bottom','multi_press_2','unknown',0,False,True),
                ('top','long_release','unknown',0,False,False),('top','multi_press_3','unknown',0,False,False),
                ('top','long_press','unknown',60,False,False),('top','long_press',None,0,False,False),
                ('top','long_press','unknown',0,True,False),('top','multi_press_2','unknown',60,False,False),
                ('bottom','multi_press_2',None,0,False,False),('bottom','multi_press_2','unknown',0,True,False)]:
                now=dt.utcnow();state=State('event.button',(now-timedelta(seconds=age)).isoformat(),
                    {'event_type':event,'restored':restored},last_changed=now)
                trigger={'id':side,'from_state':None if previous is None else State('event.button',previous),'to_state':state}
                self.assertEqual(check.async_check(variables={'trigger':trigger}),accepted)
            # Inspect the actual chosen service for all six mappings without
            # invoking another controller or performing any live API operation.
            recorded=[]
            from homeassistant.core import callback
            @callback
            def record(call):recorded.append((call.service,dict(call.data)))
            for name in ('bilresa_adjust_lights','bilresa_cycle_scenes','bilresa_all_lights_off','lighting_resume_automatic'):
                self.hass.services.async_register('script',name,record)
            for side,event,service,data in [('top','multi_press_1','bilresa_adjust_lights',{'scale':1.25}),
                    ('bottom','multi_press_1','bilresa_adjust_lights',{'scale':.8}),
                    ('top','multi_press_2','bilresa_cycle_scenes',{'direction':'next'}),
                    ('bottom','multi_press_2','bilresa_cycle_scenes',{'direction':'previous'}),
                    ('top','long_press','lighting_resume_automatic',{}),
                    ('bottom','long_press','bilresa_all_lights_off',{})]:
                recorded.clear();await self.run_sequence(AUTOMATION['actions'],{'trigger':{'id':side,'to_state':State('event.button',dt.utcnow().isoformat(),{'event_type':event})}})
                self.assertEqual(recorded,[(service,data)])
        finally:check.async_unload()
    async def test_native_scene_request_filter_and_manual_motion_gate(self):
        from homeassistant.core import Event
        from homeassistant.helpers import condition,config_validation as cv
        cfg=await cv.async_validate(self.hass,cv.CONDITION_SCHEMA,copy.deepcopy(NATIVE_SCENE['conditions'][0]))
        check=await condition.async_from_config(self.hass,cfg)
        try:
            self.assertEqual(NATIVE_SCENE['triggers'][0]['event_type'],'call_service')
            self.assertEqual(NATIVE_SCENE['triggers'][0]['event_data'],{'domain':'scene','service':'turn_on'})
            self.hass.states.async_set('scene.safe','unknown',{'entity_id':[LIGHTS[0]]})
            self.hass.states.async_set('scene.unsafe','unknown',{'entity_id':['switch.plug']})
            for entities,expected in [('scene.safe',True),(['scene.safe'],True),([],False),
                                      ('scene.unsafe',False),(['scene.safe','scene.unsafe'],False)]:
                event=Event('call_service',{'service_data':{'entity_id':entities}})
                self.assertEqual(check.async_check(variables={'trigger':{'event':event}}),expected)
        finally:check.async_unload()
        for key,zone in ZONES.items():
            self.hass.states.async_set(zone['manual'],'on')
            self.hass.states.async_set('input_boolean.lighting_manual_override','on')
            self.hass.states.async_set(zone['motion'],'on')
            self.hass.states.async_set(zone['illuminance'],'49')
            await self.run_script('lighting_manual_action',{'operation':'motion','room':key,'reason':'motion'})
            self.assertEqual(self.hass.states.get(zone['manual']).state,'off')
            self.assertEqual(self.hass.states.get(zone['active']).state,'on')

    async def test_manual_scenes_pause_only_their_targets_and_leave_automations_enabled(self):
        for members,expected in [(LIGHTS[:2],set()),([LIGHTS[2]],{'living_kitchen'}),
                ([LIGHTS[5]],{'bathroom'}),([LIGHTS[0],LIGHTS[5]],{'bathroom'}),
                ([LIGHTS[2],LIGHTS[5]],set(ZONES)),(LIGHTS,set(ZONES))]:
            for zone in ZONES.values():
                self.hass.states.async_set(zone['manual'],'off')
                self.hass.states.async_set(zone['active'],'on')
            self.hass.states.async_set('scene.scoped','unknown',{'entity_id':members})
            self.calls.clear();await self.run_script('lighting_activate_scene',{'scene_entity':'scene.scoped'})
            self.assertEqual(self.calls[-1][0],'scene')
            for key,zone in ZONES.items():
                self.assertEqual(self.hass.states.get(zone['manual']).state,'on' if key in expected else 'off')
                self.assertEqual(self.hass.states.get(zone['active']).state,'off' if key in expected else 'on')
                self.assertEqual(self.hass.states.get(zone['automation']).state,'on')
            stopped={e for d,s,data in self.calls if (d,s)==('automation','turn_off') for e in data['entity_id']}
            self.assertEqual(stopped,set())
        events=[];self.hass.bus.async_listen('ix_resume_automatic_lighting',lambda e:events.append(e))
        await self.run_script('lighting_resume_automatic',{'room':'living_kitchen'});await self.hass.async_block_till_done()
        self.assertEqual(self.hass.states.get(ZONES['bathroom']['manual']).state,'on')
        self.assertEqual(self.hass.states.get(ZONES['living_kitchen']['manual']).state,'off')
        self.assertEqual([e.data['room'] for e in events],['living_kitchen'])
        self.hass.states.async_set('scene.bedroom','unknown',{'entity_id':LIGHTS[:2]})
        self.calls.clear();await self.run_script('lighting_activate_scene',{'scene_entity':'scene.bedroom'})
        self.assertEqual(len(self.calls),1)
        self.assertEqual(self.hass.states.get(ZONES['bathroom']['manual']).state,'on')

    async def test_native_human_light_controls_not_automatic_feedback(self):
        from homeassistant.core import Event,Context
        from homeassistant.helpers import condition,config_validation as cv
        cfg=await cv.async_validate(self.hass,cv.CONDITION_SCHEMA,copy.deepcopy(NATIVE_LIGHT['conditions'][0]))
        check=await condition.async_from_config(self.hass,cfg)
        try:
            for user,expected in [(None,False),('human',True)]:
                event=Event('call_service',{'service_data':{'entity_id':LIGHTS[5]}},context=Context(user_id=user,parent_id='parent'))
                self.assertEqual(check.async_check(variables={'trigger':{'event':event}}),expected)
                if expected:await self.run_sequence(NATIVE_LIGHT['actions'],{'trigger':{'event':event}})
            self.assertEqual(self.hass.states.get(ZONES['bathroom']['manual']).state,'on')
            self.assertEqual(self.hass.states.get(ZONES['living_kitchen']['manual']).state,'off')
            self.assertFalse(any(c[0] in ['light','scene'] for c in self.calls))
        finally:check.async_unload()

    async def test_native_slider_routes_and_tracks_real_brightness_without_feedback(self):
        from homeassistant.helpers import area_registry,entity_registry
        from homeassistant.helpers.template import Template
        area=area_registry.async_get(self.hass).async_create('Bedroom');registry=entity_registry.async_get(self.hass)
        for entity,brightness in zip(LIGHTS[:2],[200,100]):
            self.hass.states.async_remove(entity)
            entry=registry.async_get_or_create('light','test',entity.split('.')[1],suggested_object_id=entity.split('.')[1])
            registry.async_update_entity(entry.entity_id,area_id=area.id)
            self.hass.states.async_set(entity,'on',{'brightness':brightness,'color_temp_kelvin':2700})
        slider=ROOM['template'][0]['light'][0]
        self.assertEqual(Template(slider['level'],self.hass).async_render(),200)
        self.calls.clear();await self.run_sequence(slider['set_level'],{'brightness':128})
        self.assertEqual({c[2]['entity_id'][0]:c[2]['brightness'] for c in self.calls},dict(zip(LIGHTS[:2],[128,64])))
        self.assertTrue(all(c[0]=='light' and set(c[2])=={'entity_id','brightness'} for c in self.calls))
        self.hass.states.async_set(LIGHTS[0],'on',{'brightness':100})
        self.hass.states.async_set(LIGHTS[1],'off',{'brightness':100})
        self.assertEqual(Template(slider['level'],self.hass).async_render(),100)
        self.calls.clear();await self.run_sequence(slider['set_level'],{'brightness':255})
        self.assertEqual(self.calls,[('light','turn_on',{'entity_id':[LIGHTS[0]],'brightness':255})])
        self.hass.states.async_set(LIGHTS[0],'off',{'brightness':100})
        self.calls.clear();await self.run_sequence(slider['set_level'],{'brightness':128})
        self.assertEqual(self.calls,[('light','turn_on',{'entity_id':sorted(LIGHTS[:2]),'brightness':128})])
        self.calls.clear();await self.run_sequence(slider['set_level'],{'brightness':0})
        self.assertEqual(self.calls,[('light','turn_off',{'entity_id':sorted(LIGHTS[:2])})])

    async def test_native_area_and_label_targets_are_lamp_only(self):
        from homeassistant.core import Event,Context
        from homeassistant.helpers import area_registry,entity_registry,label_registry
        ar=area_registry.async_get(self.hass);area=ar.async_create('Kitchen')
        label=label_registry.async_get(self.hass).async_create('Kitchen controls')
        ar.async_update(area.id,labels={label.label_id})
        er=entity_registry.async_get(self.hass)
        for entity in [LIGHTS[4],'light.extra','switch.appliance']:
            domain,name=entity.split('.',1);self.hass.states.async_remove(entity)
            entry=er.async_get_or_create(domain,'test',name,suggested_object_id=name)
            er.async_update_entity(entry.entity_id,area_id=area.id)
            self.hass.states.async_set(entity,'on',{'brightness':100})
        for data in [{'area_id':area.id},{'label_id':[label.label_id]}]:
            self.hass.states.async_set(ZONES['living_kitchen']['manual'],'off');self.calls.clear()
            event=Event('call_service',{'service_data':data},context=Context(user_id='human'))
            await self.run_sequence(NATIVE_LIGHT['actions'],{'trigger':{'event':event}})
            self.assertEqual(self.hass.states.get(ZONES['living_kitchen']['manual']).state,'on')
            self.assertEqual(self.hass.states.get(ZONES['bathroom']['manual']).state,'off')
            self.assertFalse(any(c[0] in ['light','scene'] for c in self.calls))

    async def test_resume_event_is_scoped_and_legacy_global_flag_is_ignored(self):
        from homeassistant.core import Event
        from homeassistant.helpers import condition,config_validation as cv
        motion=evaluate('motion-lighting.nix')['automation myggspray']
        for automation,own in zip(motion,['living_kitchen','bathroom']):
            checks=[await condition.async_from_config(self.hass,await cv.async_validate(self.hass,cv.CONDITION_SCHEMA,copy.deepcopy(c))) for c in automation['conditions']]
            try:
                self.hass.states.async_set('input_boolean.lighting_manual_override','on')
                self.hass.states.async_set(ZONES[own]['manual'],'off')
                for room,expected in [(own,True),('all',True),('bedroom',False),('bathroom' if own=='living_kitchen' else 'living_kitchen',False)]:
                    trigger={'id':'resume','event':Event('ix_resume_automatic_lighting',{'room':room})}
                    self.assertEqual(all(c.async_check(variables={'trigger':trigger}) for c in checks),expected)
                self.hass.states.async_set(ZONES[own]['manual'],'on')
                trigger={'id':'resume','event':Event('ix_resume_automatic_lighting',{'room':own})}
                self.assertTrue(all(c.async_check(variables={'trigger':trigger}) for c in checks))
            finally:
                for c in checks:c.async_unload()

    async def setup_priority_runtime(self):
        """Actual HA triggers/conditions/scripts; no HTTP server or device IO."""
        from homeassistant.core import callback,Context
        from homeassistant import loader
        from homeassistant.components.automation.config import PLATFORM_SCHEMA
        from homeassistant.helpers import trigger,condition,config_validation as cv
        from homeassistant.helpers.script import Script
        loader.async_setup(self.hass)
        await trigger.async_setup(self.hass)
        from homeassistant.helpers import area_registry,entity_registry
        self.fake_scene_definitions={}
        @callback
        def light(call):
            self.calls.append((call.domain,call.service,dict(call.data)))
            ids=call.data.get('entity_id',[])
            if isinstance(ids,str):ids=[ids]
            for entity in ids:
                old=self.hass.states.get(entity);attrs=dict(old.attributes if old else {})
                if 'brightness' in call.data:attrs['brightness']=call.data['brightness']
                if 'brightness_pct' in call.data:attrs['brightness']=round(255*call.data['brightness_pct']/100)
                if 'color_temp_kelvin' in call.data:
                    attrs['color_temp_kelvin']=2702 if call.data['color_temp_kelvin']==2700 else call.data['color_temp_kelvin']
                    attrs['color_mode']='color_temp'
                if 'hs_color' in call.data:attrs['hs_color']=call.data['hs_color'];attrs['color_mode']='hs'
                state=('off' if old and old.state=='on' else 'on') if call.service=='toggle' else ('on' if call.service=='turn_on' else 'off')
                self.hass.states.async_set(entity,state,attrs,context=call.context)
        self.fake_light=light
        for service in ['turn_on','turn_off','toggle']:self.hass.services.async_register('light',service,light)
        async def scene(call):
            self.calls.append((call.domain,call.service,dict(call.data)))
            ids=call.data.get('entity_id',[])
            if isinstance(ids,str):ids=[ids]
            for entity in ids:
                for lamp,settings in self.fake_scene_definitions.get(entity,{}).items():
                    await self.hass.services.async_call('light','turn_'+settings['state'],
                        {'entity_id':lamp,**{k:v for k,v in settings.items() if k!='state'}},blocking=True,context=call.context)
        self.hass.services.async_register('scene','turn_on',scene)
        areas=area_registry.async_get(self.hass);registry=entity_registry.async_get(self.hass)
        names={'bedroom':'Bedroom','living_room':'Living room','kitchen':'Kitchen','bathroom':'Bathroom'}
        area_ids={k:areas.async_create(v).id for k,v in names.items()}
        for entity,area in zip(LIGHTS,['bedroom','bedroom','living_room','living_room','kitchen','bathroom']):
            self.hass.states.async_remove(entity);name=entity.split('.')[1]
            entry=registry.async_get_or_create('light','test',name,suggested_object_id=name)
            self.assertEqual(entry.entity_id,entity);registry.async_update_entity(entity,area_id=area_ids[area])
            self.hass.states.async_set(entity,'off',{'brightness':100,'color_mode':'color_temp','color_temp_kelvin':2702})
        for z in ZONES.values():self.hass.states.async_set(z['active'],'off')
        self.trigger_unsubs=[];self.trigger_checks=[]
        for auto in MOTION_CONFIG['automation myggspray']+[NATIVE_SCENE,NATIVE_LIGHT]:
            cfg=await cv.async_validate(self.hass,PLATFORM_SCHEMA,copy.deepcopy(auto))
            checks=[await condition.async_from_config(self.hass,c) for c in cfg['conditions']]
            self.trigger_checks.extend(checks)
            worker=Script(self.hass,cfg['actions'],cfg['alias'],'automation',script_mode='queued',max_runs=5)
            self.scripts['auto_'+cfg['id']]=worker
            async def dispatch(variables,context=None,checks=checks,worker=worker):
                if all(c.async_check(variables=variables) for c in checks):
                    # AutomationEntity.async_trigger resets this same contextvar;
                    # a new automation run is not a nested caller of its trigger.
                    from homeassistant.helpers.script import script_stack_cv
                    script_stack_cv.set([])
                    await worker.async_run(variables,Context(parent_id=context.id if context else None))
            def log(level,message,**kwargs):
                if level>=40:raise AssertionError((message,kwargs))
            triggers=await trigger.async_validate_trigger_config(self.hass,cfg['triggers'])
            unsub=await trigger.async_initialize_triggers(self.hass,triggers,dispatch,'automation',cfg['alias'],log)
            self.assertIsNotNone(unsub);self.trigger_unsubs.append(unsub)
        await self.hass.async_start();await self.hass.async_block_till_done()
        for z in ZONES.values():self.assertEqual(self.hass.states.get(z['automation']).state,'on')
        self.calls.clear()
    async def occupy_dark(self,*rooms):
        for key in rooms:
            z=ZONES[key];self.hass.states.async_set(z['illuminance'],'1');self.hass.states.async_set(z['motion'],'on')
        await self.hass.async_block_till_done();self.calls.clear()
    def assert_priority_state(self,key):
        z=ZONES[key]
        for entity in z['lights']:self.assertEqual(self.hass.states.get(entity).state,'on')
        self.assertEqual(self.hass.states.get(z['manual']).state,'off')
        self.assertEqual(self.hass.states.get(z['active']).state,'on')
        self.assertEqual(self.hass.states.get(z['automation']).state,'on')
        if key=='bathroom':
            attrs=self.hass.states.get(LIGHTS[5]).attributes
            self.assertEqual(attrs['brightness'],26);self.assertEqual(attrs['color_mode'],'color_temp')
            self.assertAlmostEqual(attrs['color_temp_kelvin'],2700,delta=25)
    async def test_immediate_priority_after_room_off_and_all_off(self):
        await self.setup_priority_runtime();await self.occupy_dark(*ZONES)
        for key in ['living_kitchen','bathroom']:
            before=self.hass.states.get(ZONES[key]['motion']).last_changed
            await self.run_script('room_lights_power',{'room':key,'power':'off'})
            await self.hass.async_block_till_done();self.assert_priority_state(key)
            self.assertEqual(self.hass.states.get(ZONES[key]['motion']).last_changed,before)
        self.hass.states.async_set('switch.appliance','on')
        await self.run_script('bilresa_all_lights_off');await self.hass.async_block_till_done()
        for key in ZONES:self.assert_priority_state(key)
        for entity in LIGHTS[:2]:self.assertEqual(self.hass.states.get(entity).state,'off')
        self.assertEqual(self.hass.states.get('switch.appliance').state,'on')
        self.assertFalse(any(d=='automation' and service=='turn_off' for d,service,_ in self.calls))
        for d,service,data in self.calls:
            if d=='light':self.assertTrue(set(data['entity_id'])<=set(LIGHTS))
    async def test_native_off_and_late_physical_reports_cannot_defeat_priority(self):
        from homeassistant.core import Context
        await self.setup_priority_runtime();await self.occupy_dark('bathroom')
        for service in ['turn_off','toggle']:
            self.calls.clear()
            await self.hass.services.async_call('light',service,{'entity_id':LIGHTS[5]},blocking=True,context=Context(user_id='human'))
            await self.hass.async_block_till_done();self.assert_priority_state('bathroom')
            self.assertLess(len(self.calls),12)
        # A late native/device report, after call_service handling has finished.
        self.calls.clear();old=self.hass.states.get(LIGHTS[5]);self.hass.states.async_set(LIGHTS[5],'off',dict(old.attributes))
        await self.hass.async_block_till_done();self.assert_priority_state('bathroom')
        self.assertEqual(len([c for c in self.calls if c[0]=='light']),1)
        await self.hass.async_block_till_done();self.assertEqual(len([c for c in self.calls if c[0]=='light']),1)
    async def test_native_and_wrapped_scenes_yield_without_rewriting_definitions(self):
        from homeassistant.core import Context
        await self.setup_priority_runtime();await self.occupy_dark(*ZONES)
        definition={LIGHTS[0]:{'state':'on','brightness':128},LIGHTS[2]:{'state':'off'},LIGHTS[5]:{'state':'on','brightness':200,'color_temp_kelvin':4000}}
        self.fake_scene_definitions['scene.priority_test']=copy.deepcopy(definition)
        self.hass.states.async_set('scene.priority_test','unknown',{'entity_id':list(definition)})
        await self.run_script('lighting_activate_scene',{'scene_entity':'scene.priority_test'});await self.hass.async_block_till_done()
        for key in ZONES:self.assert_priority_state(key)
        self.assertEqual(self.hass.states.get(LIGHTS[0]).attributes['brightness'],128)
        await self.hass.services.async_call('scene','turn_on',{'entity_id':'scene.priority_test'},blocking=True,context=Context(user_id='human'))
        await self.hass.async_block_till_done()
        for key in ZONES:self.assert_priority_state(key)
        self.assertEqual(self.fake_scene_definitions['scene.priority_test'],definition)
    async def test_bathroom_priority_corrects_manual_brightness_color_without_feedback(self):
        from homeassistant.core import Context
        await self.setup_priority_runtime();await self.occupy_dark('bathroom')
        await self.hass.services.async_call('light','turn_on',{'entity_id':LIGHTS[5],'brightness':200,'hs_color':[120,100]},blocking=True,context=Context(user_id='human'))
        await self.hass.async_block_till_done();self.assert_priority_state('bathroom')
        count=len(self.calls);self.assertLess(count,15)
        old=self.hass.states.get(LIGHTS[5]);attrs=dict(old.attributes);attrs['brightness']=25
        self.hass.states.async_set(LIGHTS[5],'on',attrs)
        await self.hass.async_block_till_done();self.assertEqual(len(self.calls),count)
    async def test_bright_empty_or_invalid_sensors_preserve_manual_off(self):
        await self.setup_priority_runtime();z=ZONES['bathroom']
        for motion,lux in [('on','50'),('on','200'),('off','1'),('unknown','1'),('unavailable','1'),('on','unknown'),('on','unavailable')]:
            self.hass.states.async_set(z['illuminance'],lux);self.hass.states.async_set(z['motion'],motion)
            await self.hass.async_block_till_done()
            await self.run_script('room_lights_power',{'room':'bathroom','power':'off'});await self.hass.async_block_till_done()
            self.assertEqual(self.hass.states.get(LIGHTS[5]).state,'off',(motion,lux))
            self.assertEqual(self.hass.states.get(z['manual']).state,'on')
    async def test_slider_alone_powers_off_room_and_respects_priority(self):
        await self.setup_priority_runtime()
        from homeassistant.helpers.template import Template
        slider=next(l for l in ROOM['template'][0]['number'] if l['default_entity_id']=='number.ix_bathroom_lighting_level')
        self.assertEqual(Template(slider['state'],self.hass).async_render(),0)
        await self.run_sequence(slider['set_value'],{'value':50});await self.hass.async_block_till_done()
        self.assertEqual(self.hass.states.get(LIGHTS[5]).state,'on');self.assertEqual(self.hass.states.get(LIGHTS[5]).attributes['brightness'],128)
        self.assertEqual(Template(slider['state'],self.hass).async_render(),50)
        await self.run_sequence(slider['set_value'],{'value':0});await self.hass.async_block_till_done()
        self.assertEqual(self.hass.states.get(LIGHTS[5]).state,'off')
        self.assertEqual(Template(slider['state'],self.hass).async_render(),0)
        await self.occupy_dark('bathroom')
        await self.run_sequence(slider['set_value'],{'value':0});await self.hass.async_block_till_done();self.assert_priority_state('bathroom')
        self.assertEqual(Template(slider['state'],self.hass).async_render(),10)
    async def test_bedroom_only_action_does_not_acquire_or_command_other_zones(self):
        await self.setup_priority_runtime();await self.occupy_dark(*ZONES)
        self.calls.clear();await self.run_script('room_lights_power',{'room':'bedroom','power':'on'});await self.hass.async_block_till_done()
        self.assertEqual(self.calls,[('light','turn_on',{'entity_id':LIGHTS[:2]})])
        for key in ZONES:self.assert_priority_state(key)
    async def test_darkness_or_sensor_recovery_reclaims_existing_occupancy(self):
        await self.setup_priority_runtime();z=ZONES['bathroom']
        for previous in ['100','unknown','unavailable']:
            self.hass.states.async_set(z['illuminance'],previous)
            self.hass.states.async_set(z['motion'],'on')
            await self.hass.async_block_till_done()
            self.hass.states.async_set(z['manual'],'on')
            self.hass.states.async_set(LIGHTS[5],'off',{'brightness':128,'color_mode':'color_temp','color_temp_kelvin':4000})
            await self.hass.async_block_till_done()
            before=self.hass.states.get(z['motion']).last_changed
            self.hass.states.async_set(z['illuminance'],'1')
            await self.hass.async_block_till_done();self.assert_priority_state('bathroom')
            self.assertEqual(self.hass.states.get(z['motion']).last_changed,before)
    async def test_priority_rechecks_sensors_after_inflight_manual_command(self):
        import asyncio
        await self.setup_priority_runtime();await self.occupy_dark('bathroom')
        started=asyncio.Event();release=asyncio.Event()
        async def delayed_off(call):
            started.set();await release.wait();self.fake_light(call)
        self.hass.services.async_register('light','turn_off',delayed_off)
        task=asyncio.create_task(self.run_script('room_lights_power',{'room':'bathroom','power':'off'}))
        try:
            await asyncio.wait_for(started.wait(),5)
            self.hass.states.async_set(ZONES['bathroom']['illuminance'],'100')
            release.set();await asyncio.wait_for(task,5);await self.hass.async_block_till_done()
            self.assertEqual(self.hass.states.get(LIGHTS[5]).state,'off')
            self.assertEqual(self.hass.states.get(ZONES['bathroom']['manual']).state,'on')
            self.assertEqual(self.hass.states.get(ZONES['bathroom']['active']).state,'off')
        finally:
            release.set()
            if not task.done():task.cancel()
            await asyncio.gather(task,return_exceptions=True)
    async def test_vacancy_recovery_keeps_original_timers_and_ownership(self):
        from homeassistant.core import State
        from homeassistant.util import dt
        await self.setup_priority_runtime();await self.occupy_dark(*ZONES)
        for key,z in ZONES.items():
            for seconds,expected in [(z['idleMinutes']*60-1,'on'),(z['idleMinutes']*60+1,'off')]:
                self.hass.states._states[z['motion']]=State(z['motion'],'off',last_changed=dt.utcnow()-timedelta(seconds=seconds))
                await self.run_script('lighting_manual_action',{'operation':'motion','room':key,'reason':'recovery'});await self.hass.async_block_till_done()
                for e in z['lights']:self.assertEqual(self.hass.states.get(e).state,expected)
            self.assertEqual(self.hass.states.get(z['active']).state,'off')
            self.hass.states._states[z['motion']]=State(z['motion'],'on')
            await self.run_script('lighting_manual_action',{'operation':'motion','room':key,'reason':'recovery'});await self.hass.async_block_till_done()
            for e in z['lights']:self.assertEqual(self.hass.states.get(e).state,'off')

if __name__=='__main__':unittest.main()
