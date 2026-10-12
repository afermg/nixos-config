"""Real HA timer startup/restore semantics, with disposable state and no devices."""
import copy
from datetime import timedelta
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
CONFIG=json.loads(subprocess.check_output(['nix','eval','--impure','--json','--expr',
    f'(import {ROOT / "bilresa-lighting.nix"} {{}}).services.home-assistant.config.timer'],text=True))
HELPER=os.environ.get('IX_HA_DEPENDENCY_HELPER')
if HELPER:runpy.run_path(HELPER)['load_ha_dependencies']()

@unittest.skipUnless(HELPER,'Requires matching HA dependencies; disposable timer state only')
class LightingTimerRestoreTests(unittest.IsolatedAsyncioTestCase):
    async def test_new_running_and_offline_expired_timers(self):
        from homeassistant import loader
        from homeassistant.config_entries import ConfigEntries
        from homeassistant.core import HomeAssistant,State
        from homeassistant.helpers import area_registry,device_registry,entity_registry,floor_registry,label_registry,restore_state
        from homeassistant.helpers.json import JSONEncoder
        from homeassistant.setup import async_setup_component
        from homeassistant.util import dt
        for remaining in [None,20,-20]:
            with self.subTest(remaining=remaining),tempfile.TemporaryDirectory(prefix='lighting-timer-restore-') as directory:
                now=dt.utcnow().replace(microsecond=0)
                if remaining is not None:
                    stored=[]
                    for name in CONFIG:
                        state=State('timer.'+name,'active',{'duration':'0:00:30','restore':True,
                            'finishes_at':(now+timedelta(seconds=remaining)).isoformat()})
                        stored.append({'state':state.as_dict(),'extra_data':None,'last_seen':now.isoformat()})
                    p=Path(directory)/'.storage/core.restore_state';p.parent.mkdir()
                    p.write_text(json.dumps({'version':1,'minor_version':1,'key':'core.restore_state','data':stored},cls=JSONEncoder))
                hass=HomeAssistant(directory);loader.async_setup(hass);hass.config_entries=ConfigEntries(hass,{})
                try:
                    device_registry.async_setup(hass)
                    for registry in (floor_registry,area_registry,device_registry,entity_registry,label_registry):
                        await registry.async_load(hass,load_empty=True)
                    # Bootstrap loads restore storage before adding helper entities.
                    await restore_state.async_load(hass)
                    self.assertEqual(len(restore_state.async_get(hass).last_states),0 if remaining is None else len(CONFIG))
                    self.assertTrue(await async_setup_component(hass,'timer',{'timer':copy.deepcopy(CONFIG)}))
                    await hass.async_start();await hass.async_block_till_done()
                    for name in CONFIG:
                        state=hass.states.get('timer.'+name)
                        self.assertEqual(state.state,'active' if remaining and remaining>0 else 'idle')
                        self.assertTrue(state.attributes['restore'])
                        if remaining and remaining>0:
                            self.assertEqual(dt.parse_datetime(state.attributes['finishes_at']),now+timedelta(seconds=remaining))
                        else:self.assertNotIn('finishes_at',state.attributes)
                finally:await hass.async_stop(force=True)

if __name__=='__main__':unittest.main()
