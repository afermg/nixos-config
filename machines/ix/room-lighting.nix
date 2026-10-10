# Shared room controls for Lights; no separate Rooms dashboard or layout.
{ ... }:
let
  policy = import ./lighting-policy.nix;
  rooms = [
    { id = "bedroom"; name = "Bedroom"; }
    { id = "living_kitchen"; name = "Living room + kitchen"; }
    { id = "bathroom"; name = "Bathroom"; }
  ];
  roomContext = room: ''
    {% set allowed = ${builtins.toJSON policy.lights} %}
    {% set ns = namespace(members=[]) %}
    {% for area in ${builtins.toJSON policy.roomAreas.${room.id}} %}
      {% set ns.members = ns.members + area_entities(area) %}
    {% endfor %}
    {% set targets = allowed | select('in', ns.members) | list %}
  '';
  whiteContext = room: roomContext room + ''
    {% set colour = expand(targets) | selectattr('state', 'eq', 'on')
        | sort(attribute='entity_id') | first | default(none) %}
  '';
  roomLight = room: {
    name = "${room.name} white temperature";
    unique_id = "ix_${room.id}_white_control";
    default_entity_id = "light.ix_${room.id}_white_control";
    state = roomContext room + "{{ expand(targets) | selectattr('state', 'eq', 'on') | list | count > 0 }}";
    level = roomContext room + "{{ ([0] + (expand(targets) | selectattr('entity_id', 'in', targets) | selectattr('state', 'eq', 'on') | map(attribute='attributes.brightness', default=0) | map('int') | list)) | max }}";
    availability = roomContext room + "{{ targets | count > 0 and expand(targets) | rejectattr('state', 'in', ['unknown', 'unavailable']) | list | count > 0 }}";
    attributes.entity_id = roomContext room + "{{ targets }}";
    turn_on = [{ action = "script.room_lights_power"; data = { room = room.id; power = "on"; }; }];
    turn_off = [{ action = "script.room_lights_power"; data = { room = room.id; power = "off"; }; }];
    set_level = [{ action = "script.lighting_manual_action"; data = { operation = "level"; room = room.id; level = "{{ brightness }}"; }; }];
    # Dedicated white controls avoid the stale modes restored on obsolete
    # Rooms adapters. Their registry records are retained, not reused or reset.
    temperature = whiteContext room + "{{ (1000000 / colour.attributes.color_temp_kelvin) | round(0) if colour and colour.attributes.get('color_mode') == 'color_temp' and colour.attributes.get('color_temp_kelvin') else none }}";
    min_mireds = "{{ 153 }}"; max_mireds = "{{ 454 }}";
    set_temperature = [{ action = "script.lighting_manual_action"; data = { operation = "temperature"; room = room.id; kelvin = "{{ color_temp_kelvin }}"; }; }];
  };
  roomLevel = room: {
    name = "${room.name} brightness";
    unique_id = "ix_${room.id}_lighting_level";
    default_entity_id = "number.ix_${room.id}_lighting_level";
    min = 0; max = 100; step = 1; unit_of_measurement = "%";
    availability = (roomLight room).availability;
    state = roomContext room + ''
      {% set brightest = ([0] + (expand(targets) | selectattr('entity_id', 'in', targets)
          | selectattr('state', 'eq', 'on') | map(attribute='attributes.brightness', default=0)
          | map('int') | list)) | max %}
      {{ [1, (brightest * 100 / 255) | round(0)] | max if brightest > 0 else 0 }}
    '';
    set_value = [{ action = "script.lighting_manual_action";
      data = { operation = "level"; room = room.id; level = "{{ ((value | float) * 255 / 100) | round(0) | int }}"; }; }];
  };
in {
  services.home-assistant.config = {
    template = [{
      light = builtins.map roomLight rooms;
      number = builtins.map roomLevel rooms;
    }];
    script = {
      room_lights_power = {
        alias = "Room lights - Manual on/off";
        mode = "queued";
        fields = {
          room = { required = true; selector.select.options = policy.rooms; };
          power = { required = true; selector.select.options = [ "on" "off" ]; };
        };
        sequence = [
          { condition = "template"; value_template = "{{ room | default('') in ${builtins.toJSON (builtins.attrNames policy.roomAreas)} and power | default('') in ['on', 'off'] }}"; }
          { action = "script.lighting_manual_action"; data = { operation = "{{ 'room_' ~ power }}"; room = "{{ room }}"; }; }
        ];
      };
      room_lights_proportional = {
        alias = "Room lights - Proportional brightness";
        description = "Adjust lit lamps only; living/kitchen share an equal level, other rooms preserve balance. Keep white temperature, exclude plugs, and retain motion priority.";
        icon = "mdi:brightness-percent";
        mode = "queued";
        max = 10;
        fields = {
          room = { name = "Room"; required = true; selector.select.options = policy.rooms; };
          scale = { name = "Brightness multiplier"; required = true; default = 1.25;
            selector.number = { min = 0.1; max = 2; step = 0.05; mode = "box"; }; };
        };
        sequence = [
          { condition = "template"; value_template = "{{ room | default('') in ${builtins.toJSON (builtins.attrNames policy.roomAreas)} and is_number(scale | default(none)) and 0 < scale | float(0) <= 2 }}"; }
          { action = "script.lighting_manual_action"; data = { operation = "brightness"; room = "{{ room }}"; scale = "{{ scale }}"; }; }
        ];
      };
    };
  };
}
