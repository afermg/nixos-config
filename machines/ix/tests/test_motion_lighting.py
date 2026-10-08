"""Nix policy and actual HA condition matrices; never touch live hardware."""
import copy
from datetime import timedelta
import json,os,runpy,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def evaluate(file):
    return json.loads(subprocess.check_output(['nix','eval','--impure','--json','--expr',
        f'(import {ROOT / file} {{}}).services.home-assistant.config'],text=True))
CONFIG=evaluate('motion-lighting.nix')
POLICY=json.loads(subprocess.check_output(['nix','eval','--impure','--json','--expr',f'import {ROOT / "lighting-policy.nix"}'],text=True))
ZONES=POLICY['motionZones'];AUTOS=CONFIG['automation myggspray']
WORKER=CONFIG['script']['lighting_motion_priority']['sequence']
def choices(seq,key):
    return next(c for c in seq[1]['choose'] if c['conditions']=="{{ room == '"+key+"' }}")['sequence'][0]['choose']

class MotionPolicyTests(unittest.TestCase):
    def test_module_imports_and_restored_helpers(self):
        self.assertIn('./motion-lighting.nix',(ROOT/'services.nix').read_text())
        for helper in CONFIG['input_boolean'].values():self.assertNotIn('initial',helper)
    def test_all_motion_uses_the_shared_queue(self):
        for auto,key in zip(AUTOS,['living_kitchen','bathroom']):
            self.assertTrue(auto['initial_state']);self.assertEqual(auto['mode'],'queued')
            self.assertEqual(auto['actions'],[{'action':'script.lighting_manual_action',
                'data':{'operation':'motion','room':key,'reason':'{{ trigger.id }}'}}])
            self.assertNotIn('lighting_manual_override',json.dumps(auto))
            self.assertNotIn('lighting_manual_'+key,json.dumps(auto['conditions']))
    def test_exact_unchanged_vacancy_and_darkness_rules(self):
        for auto,key in zip(AUTOS,['living_kitchen','bathroom']):
            z=ZONES[key];triggers={t['id']:t for t in auto['triggers']}
            self.assertEqual(triggers['idle'],{'trigger':'state','entity_id':z['motion'],'to':'off','for':{'minutes':z['idleMinutes']},'id':'idle'})
            self.assertEqual(triggers['dark'],{'trigger':'numeric_state','entity_id':z['illuminance'],'below':50,'id':'dark'})
            self.assertEqual(triggers['recovery'],{'trigger':'time_pattern','minutes':'/1','id':'recovery'})
            on,off=choices(WORKER,key)
            self.assertIn({'condition':'numeric_state','entity_id':z['illuminance'],'below':50},on['conditions'])
            self.assertIn({'condition':'state','entity_id':z['motion'],'state':'on'},on['conditions'])
            self.assertNotIn(z['illuminance'],json.dumps(off))
            self.assertIn(str(60*z['idleMinutes']),off['conditions'][-1]['value_template'])
            self.assertEqual(off['sequence'][0],{'action':'light.turn_off','target':{'entity_id':z['lights']}})
            self.assertEqual(off['sequence'][1],{'action':'input_boolean.turn_off','target':{'entity_id':z['active']}})
    def test_immediate_manual_and_lamp_report_triggers_without_delays(self):
        for auto,key in zip(AUTOS,['living_kitchen','bathroom']):
            z=ZONES[key];triggers={t['id']:t for t in auto['triggers']}
            self.assertEqual(triggers['lamp'],{'trigger':'state','entity_id':z['lights'],'id':'lamp'})
            self.assertEqual(triggers['manual'],{'trigger':'state','entity_id':z['manual'],'to':'on','id':'manual'})
        self.assertNotIn('"delay"',json.dumps(CONFIG));self.assertNotIn('"wait_for_trigger"',json.dumps(CONFIG))
    def test_priority_claims_and_clears_manual_before_commands(self):
        for key,z in ZONES.items():
            seq=choices(WORKER,key)[0]['sequence']
            self.assertEqual(seq[0]['then'][0],{'action':'input_boolean.turn_off','target':{'entity_id':z['manual']}})
            self.assertEqual(seq[1]['then'][0],{'action':'input_boolean.turn_on','target':{'entity_id':z['active']}})
            self.assertEqual(seq[-1]['action'],'light.turn_on')
            self.assertIn('lamp.attributes.entity_id is not defined',seq[2]['variables']['needed'])
        self.assertNotIn('data',choices(WORKER,'living_kitchen')[0]['sequence'][-1])
        self.assertEqual(choices(WORKER,'bathroom')[0]['sequence'][-1]['data'],{'brightness_pct':10,'color_temp_kelvin':2700})
    def test_recovery_cannot_independently_turn_lamps_on(self):
        router=evaluate('bilresa-lighting.nix')['script']['lighting_manual_action']['sequence']
        branch=next(c for c in router[-1]['choose'] if c['conditions']=="{{ operation == 'motion' }}")
        self.assertEqual(branch['sequence'][0]['data']['can_activate'],"{{ reason | default('') not in ['idle', 'recovery'] }}")

HELPER=os.environ.get('IX_HA_DEPENDENCY_HELPER')
if HELPER:runpy.run_path(HELPER)['load_ha_dependencies']()
@unittest.skipUnless(HELPER,'Matching HA dependencies required')
class HomeAssistantConditionTests(unittest.IsolatedAsyncioTestCase):
    async def check_cases(self,key,cases):
        from homeassistant.core import HomeAssistant,State
        from homeassistant.helpers import condition,config_validation as cv
        from homeassistant.exceptions import ConditionError
        from homeassistant.util import dt
        with tempfile.TemporaryDirectory(prefix='motion-priority-conditions-') as directory:
            hass=HomeAssistant(directory);groups=[];z=ZONES[key]
            try:
                await cv.async_validate(hass,cv.SCRIPT_SCHEMA,copy.deepcopy(WORKER))
                for branch in choices(WORKER,key):
                    groups.append([await condition.async_from_config(hass,await cv.async_validate(hass,cv.CONDITION_SCHEMA,copy.deepcopy(c))) for c in branch['conditions']])
                for case in cases:
                    trigger,motion,lux,owned,seconds,light,expected=case[:7];manual=case[7] if len(case)>7 else 'off'
                    with self.subTest(key=key,case=case):
                        hass.states._states[z['motion']]=State(z['motion'],motion,last_changed=dt.utcnow()-timedelta(seconds=seconds))
                        for entity,value in [(z['illuminance'],lux),(z['active'],owned),(z['manual'],manual)]:hass.states.async_set(entity,value)
                        for entity in z['lights']:hass.states.async_set(entity,light)
                        selected=None
                        for i,checks in enumerate(groups):
                            try:matched=all(c.async_check(variables={'can_activate':trigger not in ['idle','recovery']}) for c in checks)
                            except ConditionError:matched=False
                            if matched:selected=i;break
                        self.assertEqual(selected,expected)
            finally:
                for group in groups:
                    for c in group:c.async_unload()
                await hass.async_stop(force=True)
    async def test_actual_ha_living_kitchen_matrix(self):
        await self.check_cases('living_kitchen',[
            ('motion','on','49','off',0,'off',0),('motion','on','50','off',0,'off',None),
            ('motion','on','100','off',0,'off',None),('motion','on','unknown','off',0,'off',None),
            ('motion','on','unavailable','off',0,'off',None),('dark','on','1','off',0,'off',0),
            ('dark','off','1','off',700,'off',None),('idle','off','200','on',601,'on',1),
            ('idle','off','unknown','on',601,'on',1),('recovery','off','1','on',599,'on',None),
            ('recovery','off','1','on',601,'on',1),('recovery','off','1','off',601,'on',None),
            ('motion','on','200','on',0,'on',None),('idle','on','1','on',700,'on',None),
            ('recovery','unavailable','1','on',700,'on',None),('recovery','unknown','1','on',700,'on',None),
            ('startup','on','1','on',0,'off',0),('startup','off','1','on',0,'on',None),
            ('recovery','on','1','off',0,'off',None),
            ('manual','on','1','off',0,'off',0,'on'),('lamp','on','1','off',0,'off',0,'on'),
            ('manual','on','100','off',0,'off',None,'on'),('idle','off','1','on',601,'on',None,'on'),
        ])
    async def test_actual_ha_bathroom_matrix(self):
        await self.check_cases('bathroom',[
            ('motion','on','49','off',0,'off',0),('motion','on','50','off',0,'off',None),
            ('motion','on','unknown','off',0,'off',None),('motion','on','1','off',0,'on',0),
            ('motion','on','1','on',0,'on',0),('motion','on','1','off',0,'unavailable',None),
            ('dark','on','1','off',0,'off',0),('dark','off','1','off',400,'off',None),
            ('idle','off','200','on',301,'on',1),('idle','off','unknown','on',301,'on',1),
            ('recovery','off','1','on',299,'on',None),('recovery','off','1','on',301,'on',1),
            ('recovery','off','1','off',301,'on',None),('idle','on','1','on',400,'on',None),
            ('recovery','unavailable','1','on',400,'on',None),('recovery','unknown','1','on',400,'on',None),
            ('startup','on','1','off',0,'off',0),('startup','on','1','off',0,'on',0),
            ('startup','off','1','on',0,'on',None),
            ('manual','on','1','off',0,'on',0,'on'),('lamp','on','1','off',0,'off',0,'on'),
            ('lamp','on','unavailable','off',0,'off',None,'on'),
        ])
if __name__=='__main__':unittest.main()
