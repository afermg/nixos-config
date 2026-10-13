"""One-time, editable, scoped scene seeds; never activate live scenes."""
import json
from pathlib import Path
import subprocess
import unittest
ROOT=Path(__file__).resolve().parents[1]
class ScenePolicyTests(unittest.TestCase):
    def test_editable_seed_does_not_overwrite_existing_scenes(self):
        module=json.loads(subprocess.check_output(['nix','eval','--impure','--json','--expr',
            f'(import {ROOT / "lighting-scenes.nix"} {{lib.mkAfter = x: x;}})'],text=True))
        self.assertEqual(module['services']['home-assistant']['config'],{'scene ui':'!include /var/lib/hass/scenes.yaml'})
        seed=module['systemd']['services']['home-assistant']['preStart']
        self.assertIn('! -e /var/lib/hass/scenes.yaml',seed)
        self.assertIn('! -L /var/lib/hass/scenes.yaml',seed)
    def test_only_four_scoped_medium_full_presets_no_legacy_or_bathroom(self):
        policy=json.loads(subprocess.check_output(['nix','eval','--impure','--json','--expr',f'import {ROOT / "lighting-policy.nix"}'],text=True))
        scenes={s['id']:s for s in json.loads((ROOT/'lighting-scenes-defaults.json').read_text())}
        self.assertEqual(set(scenes),{e.removeprefix('scene.') for ids in policy['sceneCycles'].values() for e in ids})
        self.assertNotIn('living_kitchen_only',scenes)
        for room,members in [('bedroom',policy['lights'][:2]),('living_kitchen',policy['lights'][2:5])]:
            for entity,brightness in zip(policy['sceneCycles'][room],[128,255]):
                self.assertEqual(scenes[entity.removeprefix('scene.')]['entities'],{e:{'state':'on','brightness':brightness} for e in members})
        self.assertEqual(policy['roomAreas']['bedroom'],['bedroom'])
        self.assertNotIn('bedroom_bathroom',policy['roomAreas'])
        self.assertNotIn('bathroom',policy['bilresa'])
if __name__=='__main__':unittest.main()
