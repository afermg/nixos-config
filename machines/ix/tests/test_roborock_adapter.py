"""Matching HA adapter tests, using only disposable HA and fake robot services."""
import asyncio, importlib.util, os, runpy, sys, tempfile, unittest
from pathlib import Path
from types import SimpleNamespace as NS
from unittest.mock import patch
HELPER=os.environ.get('IX_HA_DEPENDENCY_HELPER')
ROOT=Path(__file__).resolve().parents[1]
if HELPER:
    runpy.run_path(HELPER)['load_ha_dependencies']()
    import homeassistant  # Framework initializes voluptuous/probatio before integrations.
    spec=importlib.util.spec_from_file_location('ix_adapter_test',ROOT/'ha-components/custom_components/ix_roborock_sequence/__init__.py',submodule_search_locations=[str(ROOT/'ha-components/custom_components/ix_roborock_sequence')])
    adapter=importlib.util.module_from_spec(spec);sys.modules[spec.name]=adapter;spec.loader.exec_module(adapter)

@unittest.skipUnless(HELPER,'Matching HA dependencies required')
class AdapterTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        from homeassistant.core import HomeAssistant,Context
        self.temp=tempfile.TemporaryDirectory();self.hass=HomeAssistant(self.temp.name)
        from homeassistant.helpers import area_registry,device_registry,entity_registry,label_registry,floor_registry
        device_registry.async_setup(self.hass)
        for registry in (floor_registry,area_registry,device_registry,entity_registry,label_registry):
            await registry.async_load(self.hass,load_empty=True)
        self.m=adapter.Manager(self.hass);self.m.context=Context();self.commands=[]
        async def command(call):self.commands.append((call.domain,call.service,dict(call.data)))
        for domain,name in [('vacuum','send_command'),('vacuum','stop'),('vacuum','return_to_base'),('vacuum','set_fan_speed'),('select','select_option')]:
            self.hass.services.async_register(domain,name,command)
    async def asyncTearDown(self):
        if self.m.task and not self.m.task.done():
            self.m.task.cancel()
            try:await self.m.task
            except asyncio.CancelledError:pass
        await self.hass.async_stop(force=True);self.temp.cleanup()
    async def test_commands_target_only_original_robot(self):
        await self.m.command('mode','vacuum');await self.m.command('start',None)
        self.assertEqual(self.commands,[('select','select_option',{'entity_id':adapter.MODE,'option':'vacuum'}),('vacuum','send_command',{'entity_id':adapter.VACUUM,'command':'app_start'})])
        await self.m.cancel(NS(context=self.m.context));self.assertEqual(len(self.commands),2)
    async def test_no_robot_no_start(self):
        from homeassistant.exceptions import HomeAssistantError
        with self.assertRaises(HomeAssistantError):await self.m.start(NS(context=self.m.context))
        self.assertFalse(self.commands)
    async def test_cancel_only_active_sequence_and_dock(self):
        self.m.task=asyncio.create_task(asyncio.sleep(30))
        await self.m.cancel(NS(context=self.m.context))
        self.assertEqual([x[:2] for x in self.commands],[('vacuum','stop'),('vacuum','return_to_base')])
        self.commands.clear();await self.m.cancel(NS(context=self.m.context));self.assertFalse(self.commands)
    async def test_double_start_is_rejected(self):
        from homeassistant.exceptions import HomeAssistantError
        self.m.task=asyncio.create_task(asyncio.sleep(30))
        with self.assertRaises(HomeAssistantError):await self.m.start(NS(context=self.m.context))
        self.assertFalse(self.commands)
    async def test_brief_pause_and_external_commands_are_latched(self):
        from homeassistant.core import Event,State,Context
        self.m.task=asyncio.create_task(asyncio.sleep(30));self.m.runner=NS(abort_reason=None,expected_mode='vacuum')
        self.m.interrupted(Event('state_changed',{'new_state':State(adapter.VACUUM,'paused')}))
        self.assertIsNotNone(self.m.runner.abort_reason)
        self.m.runner.abort_reason=None
        data={'domain':'vacuum','service':'stop','service_data':{'entity_id':adapter.VACUUM}}
        self.m.manual_command(Event('call_service',data,context=self.m.context));self.assertIsNone(self.m.runner.abort_reason)
        self.m.manual_command(Event('call_service',data,context=Context()));self.assertIsNotNone(self.m.runner.abort_reason)
    async def test_snapshot_reuses_coordinator_and_exposes_completion_without_credentials(self):
        from roborock.data import CleanRecord,RoborockFinishReason,RoborockCleanType
        state=NS(state_name='charging',in_cleaning=0,in_returning=0,error_code=0,battery=97,
                 current_cleaning_mode_name='custom',fan_speed_name='custom',water_mode_name='custom',mop_route_name='custom')
        record=CleanRecord(begin=100,end=200,complete=1,error=0,clean_type=RoborockCleanType.all_zone,finish_reason=RoborockFinishReason.finished_cleaning,map_flag=0)
        coordinator=NS(last_update_success=True,data=object(),properties_api=NS(status=state,maps=NS(current_map=0),clean_summary=NS(last_clean_record=record)))
        self.hass.states.async_set(adapter.VACUUM,'docked')
        for suffix,value in [('mop_attached','on'),('water_box_attached','on'),('water_shortage','off'),('dock_dirty_water_box','off'),('dock_clean_water_box','off')]:
            self.hass.states.async_set('binary_sensor.'+adapter.PREFIX+'_'+suffix,value)
        self.hass.states.async_set('sensor.'+adapter.PREFIX+'_dock_dock_error','ok')
        with patch.object(self.m,'coordinator',return_value=coordinator):
            s=self.m.snapshot();self.assertTrue(s['available']);self.assertTrue(s['mop_ready'])
            self.assertEqual(s['record']['finish_reason'],52);self.assertEqual(s['record']['clean_type'],1)
            self.assertNotIn('token',str(s));self.assertFalse(self.commands)
    async def test_setup_registers_only_no_start_actions(self):
        from unittest.mock import AsyncMock
        with patch.object(adapter.discovery,'async_load_platform',new=AsyncMock()) as load:
            self.assertTrue(await adapter.async_setup(self.hass,{adapter.DOMAIN:{}}))
            await self.hass.async_block_till_done()
            self.assertTrue(self.hass.services.has_service(adapter.DOMAIN,'start'))
            self.assertTrue(self.hass.services.has_service(adapter.DOMAIN,'inspect'))
            self.assertIsNone(self.hass.data[adapter.DOMAIN].task)
            self.assertFalse(self.commands);load.assert_awaited_once()
        self.assertEqual(adapter.CONFIG_SCHEMA({adapter.DOMAIN:{}}),{adapter.DOMAIN:{}})

if __name__=='__main__':unittest.main()
