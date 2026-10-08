"""One-time, editable, lamp-only scenes; no activation in these tests."""
import json
from pathlib import Path
import subprocess
import unittest
ROOT=Path(__file__).resolve().parents[1]
class LightingSceneTests(unittest.TestCase):
    def test_ui_include_and_non_destructive_seed(self):
        module=json.loads(subprocess.check_output(['nix','eval','--impure','--json','--expr',
            f'(import {ROOT / "lighting-scenes.nix"} {{lib.mkAfter = x: x;}})'],text=True))
        self.assertEqual(module['services']['home-assistant']['config'],{'scene ui':'!include /var/lib/hass/scenes.yaml'})
        seed=module['systemd']['services']['home-assistant']['preStart']
        self.assertIn('! -e /var/lib/hass/scenes.yaml',seed)
        self.assertIn('! -L /var/lib/hass/scenes.yaml',seed)
        self.assertIn('install -m 0600',seed)
    def test_defaults_cover_only_six_known_lamps_without_color_changes(self):
        scenes=json.loads((ROOT/'lighting-scenes-defaults.json').read_text())
        allowed=json.loads(subprocess.check_output(['nix','eval','--impure','--json','--expr',f'(import {ROOT / "lighting-policy.nix"}).lights'],text=True))
        self.assertEqual([s['id'] for s in scenes],['bedroom_medium_illumination','living_kitchen_only',
            'bedroom_full_illumination','living_kitchen_medium_illumination'])
        for s in scenes:
            self.assertTrue(s['entities'])
            self.assertLessEqual(set(s['entities']),set(allowed))
            for value in s['entities'].values():self.assertLessEqual(set(value),{'state','brightness'})
        self.assertEqual(set(scenes[0]['entities']),set(allowed[:2]))
        self.assertEqual(set(scenes[1]['entities']),set(allowed))
        self.assertEqual(scenes[2]['entities'],{e:{'state':'on','brightness':255} for e in allowed[:2]})
        self.assertEqual(scenes[3]['entities'],{e:{'state':'on','brightness':128} for e in allowed[2:5]})
        self.assertEqual(scenes[0]['entities'][allowed[0]],{'state':'on','brightness':128})
        self.assertEqual(scenes[0]['entities'][allowed[1]],{'state':'on','brightness':128})
        self.assertFalse(set(scenes[0]['entities']) & set(allowed[2:]))
if __name__=='__main__':unittest.main()
