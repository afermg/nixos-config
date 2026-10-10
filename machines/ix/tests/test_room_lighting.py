"""Shared Lights controls; redundant Rooms dashboard/layout is intentionally absent."""
import json
from pathlib import Path
import subprocess
import unittest
ROOT=Path(__file__).resolve().parents[1]
CONFIG=json.loads(subprocess.check_output(['nix','eval','--impure','--json','--expr',
    f'(import {ROOT / "room-lighting.nix"} {{}}).services.home-assistant.config'],text=True))
class RoomLightingPolicyTests(unittest.TestCase):
    def test_no_redundant_rooms_dashboard_or_layout_code(self):
        self.assertNotIn('lovelace',CONFIG)
        text=(ROOT/'room-lighting.nix').read_text()
        for fragment in ['roomCard =','dashboard =','pkgs.writeText','type = "tile"','type = "button"']:
            self.assertNotIn(fragment,text)
    def test_shared_controls_keep_ids_and_use_safe_queue(self):
        self.assertEqual(len(CONFIG['template'][0]['number']),3)
        self.assertEqual(len(CONFIG['template'][0]['light']),3)
        self.assertTrue(all(l['default_entity_id'].endswith('_white_control') for l in CONFIG['template'][0]['light']))
        for room in ['bedroom','living_kitchen','bathroom']:
            number=next(n for n in CONFIG['template'][0]['number'] if n['default_entity_id']=='number.ix_'+room+'_lighting_level')
            self.assertEqual((number['min'],number['max'],number['step']),(0,100,1))
            self.assertEqual(number['set_value'][0]['action'],'script.lighting_manual_action')
            self.assertEqual(number['set_value'][0]['data']['room'],room)
            white=next(l for l in CONFIG['template'][0]['light'] if l['default_entity_id']=='light.ix_'+room+'_white_control')
            self.assertEqual(white['set_temperature'][0],{'action':'script.lighting_manual_action',
                'data':{'operation':'temperature','room':room,'kelvin':'{{ color_temp_kelvin }}'}})
            for unsupported in ['set_hs','hs','set_rgb','rgb','set_xy','xy']:
                self.assertNotIn(unsupported,white)
            for power in ['on','off']:
                self.assertEqual(white['turn_'+power],[{'action':'script.room_lights_power','data':{'room':room,'power':power}}])
    def test_selectors_keep_three_zones_and_original_areas(self):
        for name in ['room_lights_power','room_lights_proportional']:
            self.assertEqual(CONFIG['script'][name]['fields']['room']['selector']['select']['options'],['bedroom','living_kitchen','bathroom'])
        p=json.loads(subprocess.check_output(['nix','eval','--impure','--json','--expr',f'import {ROOT / "lighting-policy.nix"}'],text=True))
        self.assertEqual(p['roomAreas']['living_kitchen'],['living_room','kitchen'])
        self.assertEqual(p['roomAreas']['living_room'],['living_room']);self.assertEqual(p['roomAreas']['kitchen'],['kitchen'])
if __name__=='__main__':unittest.main()
