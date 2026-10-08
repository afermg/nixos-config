"""Room dashboard uses the shared safe queue; runtime coverage is in button tests."""
import json
from pathlib import Path
import subprocess
import unittest
ROOT=Path(__file__).resolve().parents[1]
CONFIG=json.loads(subprocess.check_output(['nix','eval','--impure','--json','--expr',
    f'(import {ROOT / "room-lighting.nix"} {{pkgs.writeText = name: text: text;}}).services.home-assistant.config'],text=True))
DASH=CONFIG['lovelace']['dashboards']['room-lighting']
CARDS=json.loads(DASH['filename'])['views'][0]['cards']
class RoomLightingPolicyTests(unittest.TestCase):
    def test_separate_dashboard_and_status(self):
        self.assertEqual(DASH['mode'],'yaml');self.assertTrue(DASH['show_in_sidebar'])
        self.assertEqual(CARDS[1]['type'],'markdown')
        self.assertNotIn('input_boolean.lighting_manual_override',json.dumps(CARDS))
    def test_room_controls_use_safe_manual_scripts(self):
        cards=[c for c in CARDS if c['type']=='vertical-stack']
        self.assertEqual(len(cards),3)
        for room,name,card in zip(('bedroom','living_kitchen','bathroom'),
                ('Bedroom','Living room + kitchen','Bathroom'),cards):
            self.assertEqual(card['cards'][0]['content'],'## '+name)
            buttons=card['cards'][1]['cards']
            self.assertEqual([b['name'] for b in buttons],['On','Off'])
            for b,power in zip(buttons[:2],('on','off')):
                self.assertEqual(b['tap_action']['perform_action'],'script.room_lights_power')
                self.assertEqual(b['tap_action']['data'],{'room':room,'power':power})
            slider=card['cards'][2]
            self.assertEqual(slider['features'],[{'type':'light-brightness'}])
            self.assertEqual(slider['entity'],'light.ix_'+room+'_lighting_control')
            if room!='bedroom':
                self.assertEqual(card['cards'][3]['entity'],'input_boolean.lighting_manual_'+room)
                self.assertEqual(card['cards'][4]['tap_action']['data'],{'room':room})
            else:self.assertEqual(len(card['cards']),3)
    def test_scene_and_resume_buttons(self):
        self.assertEqual([b['tap_action']['perform_action'] for b in CARDS[2]['cards']],
                         ['script.lighting_resume_automatic','script.bilresa_all_lights_off'])
        for b in CARDS[3]['cards']:self.assertEqual(b['tap_action']['perform_action'],'script.lighting_activate_scene')
        self.assertEqual([b['tap_action']['data']['scene_entity'] for b in CARDS[3]['cards']],
            ['scene.bedroom_medium_illumination','scene.bedroom_full_illumination',
             'scene.living_kitchen_medium_illumination','scene.living_kitchen_only'])
        self.assertNotIn('light.turn_on',json.dumps(CARDS))
    def test_selectors_offer_three_zones_not_merged_ha_areas(self):
        for name in ['room_lights_power','room_lights_proportional']:
            self.assertEqual(CONFIG['script'][name]['fields']['room']['selector']['select']['options'],
                             ['bedroom','living_kitchen','bathroom'])
        policy=json.loads(subprocess.check_output(['nix','eval','--impure','--json','--expr',
            f'import {ROOT / "lighting-policy.nix"}'],text=True))
        self.assertEqual(policy['roomAreas']['living_kitchen'],['living_room','kitchen'])
        self.assertEqual(policy['roomAreas']['living_room'],['living_room'])
        self.assertEqual(policy['roomAreas']['kitchen'],['kitchen'])
if __name__=='__main__':unittest.main()
