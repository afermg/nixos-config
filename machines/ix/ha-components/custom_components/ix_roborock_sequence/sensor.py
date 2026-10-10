"""Sequence status only; the original robot entities remain authoritative."""
from homeassistant.components.sensor import SensorEntity
from homeassistant.helpers.dispatcher import async_dispatcher_connect
from . import DOMAIN, SIGNAL


async def async_setup_platform(hass, config, async_add_entities, discovery_info=None):
    async_add_entities([SequenceSensor(hass.data[DOMAIN])])


class SequenceSensor(SensorEntity):
    _attr_name = "Vacuum then mop"
    _attr_unique_id = "ix_roborock_sequence_status"
    _attr_should_poll = False
    _attr_icon = "mdi:robot-vacuum"

    def __init__(self, manager):
        self.manager = manager
        self.entity_id = "sensor.ix_roborock_sequence"

    @property
    def native_value(self):
        return self.manager.phase

    @property
    def extra_state_attributes(self):
        return {"message": self.manager.message, "running": bool(self.manager.task and not self.manager.task.done())}

    async def async_added_to_hass(self):
        self.async_on_remove(async_dispatcher_connect(self.hass, SIGNAL, self.async_write_ha_state))
