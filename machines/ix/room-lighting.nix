# Separate dashboard; all manual commands share the serialized lighting queue.
{ pkgs, ... }:
let
  policy = import ./lighting-policy.nix;
  rooms = [
    { id = "bedroom"; name = "Bedroom"; }
    { id = "living_kitchen"; name = "Living room + kitchen"; }
    { id = "bathroom"; name = "Bathroom"; }
  ];
  button = name: icon: service: data: {
    type = "button"; inherit name icon;
    tap_action = { action = "perform-action"; perform_action = service; inherit data; };
  };
  roomContext = room: ''
    {% set allowed = ${builtins.toJSON policy.lights} %}
    {% set ns = namespace(members=[]) %}
    {% for area in ${builtins.toJSON policy.roomAreas.${room.id}} %}
      {% set ns.members = ns.members + area_entities(area) %}
    {% endfor %}
    {% set targets = allowed | select('in', ns.members) | list %}
  '';
  roomLight = room: {
    name = "${room.name} lighting control";
    unique_id = "ix_${room.id}_lighting_control";
    default_entity_id = "light.ix_${room.id}_lighting_control";
    state = roomContext room + "{{ expand(targets) | selectattr('state', 'eq', 'on') | list | count > 0 }}";
    level = roomContext room + "{{ ([0] + (expand(targets) | selectattr('entity_id', 'in', targets) | selectattr('state', 'eq', 'on') | map(attribute='attributes.brightness', default=0) | map('int') | list)) | max }}";
    availability = roomContext room + "{{ targets | count > 0 and expand(targets) | rejectattr('state', 'in', ['unknown', 'unavailable']) | list | count > 0 }}";
    attributes.entity_id = roomContext room + "{{ targets }}";
    turn_on = [{ action = "script.room_lights_power"; data = { room = room.id; power = "on"; }; }];
    turn_off = [{ action = "script.room_lights_power"; data = { room = room.id; power = "off"; }; }];
    set_level = [{ action = "script.lighting_manual_action"; data = { operation = "level"; room = room.id; level = "{{ brightness }}"; }; }];
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
  roomCard = room: {
    type = "vertical-stack";
    cards = [
      { type = "markdown"; content = "## ${room.name}"; }
      { type = "tile"; entity = "number.ix_${room.id}_lighting_level"; name = "Brightness (0 = off)";
        tap_action.action = "none"; icon_tap_action.action = "none";
        features = [{ type = "numeric-input"; style = "slider"; }]; }
    ] ++ (if builtins.hasAttr room.id policy.motionZones then [
      { type = "entity"; entity = policy.motionZones.${room.id}.manual;
        name = "Manual lighting (dark occupancy overrides)"; tap_action.action = "none"; }
      (button "Resume motion here" "mdi:motion-sensor" "script.lighting_resume_automatic" { room = room.id; })
    ] else []);
  };
  dashboard = {
    title = "Room lighting";
    views = [{
      title = "Rooms"; path = "rooms";
      cards = [
        { type = "markdown"; content = "BILRESA: top short = brighter; bottom short = dimmer; top double = next scene; bottom double = previous scene; top long = Resume automatic lighting; bottom long = six lamps off. Dark occupancy immediately overrides scene/manual settings in the affected area, including Off. Sliders alone control each room: zero turns it off; raising an entirely off room turns it on. Otherwise sliders scale lit lamps together, preserving balance/colors. Bathroom dark occupancy enforces its 10% / 2700 K night light. No appliance plugs are included."; }
        { type = "markdown"; content = "Bedroom-only lighting does not affect either motion sensor. Motion automations stay enabled. Manual ownership applies only without dark occupancy; priority returns immediately, without waiting for new motion. Top long-press resumes both areas."; }
        {
          type = "grid"; columns = 2; square = false;
          cards = [
            (button "Resume automatic lighting" "mdi:motion-sensor" "script.lighting_resume_automatic" { })
            (button "All lights off (manual)" "mdi:lightbulb-group-off" "script.bilresa_all_lights_off" { })
          ];
        }
        {
          type = "grid"; columns = 2; square = false;
          cards = [
            (button "Bedroom medium" "mdi:bed" "script.lighting_activate_scene" { scene_entity = "scene.bedroom_medium_illumination"; })
            (button "Bedroom full" "mdi:bed" "script.lighting_activate_scene" { scene_entity = "scene.bedroom_full_illumination"; })
            (button "Living + kitchen medium" "mdi:sofa" "script.lighting_activate_scene" { scene_entity = "scene.living_kitchen_medium_illumination"; })
            (button "Living + kitchen only" "mdi:sofa" "script.lighting_activate_scene" { scene_entity = "scene.living_kitchen_only"; })
          ];
        }
        {
          type = "markdown";
          content = "Edit scenes in Settings → Automations & scenes. Label scenes **Button scenes** to include them in the button cycle (entity-ID order). Scenes must contain only the six individual lamps, not groups or plugs. Defaults are seeded once; later edits are retained. Scenes and direct lamp controls cannot hold an occupied, dark area off. Other areas remain unaffected. Scenes with explicit off commands in other rooms affect those rooms too.";
        }
      ] ++ builtins.map roomCard rooms;
    }];
  };
in
{
  services.home-assistant.config = {
    template = [{
      # Keep existing light adapters/IDs for compatibility; the displayed number
      # sliders reach zero (HA's light-brightness feature has a minimum of 1%).
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
        description = "Scale lit lamps together, preserve color/balance and exclude plugs. Dark occupancy immediately takes precedence.";
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
    lovelace.dashboards.room-lighting = {
      mode = "yaml"; title = "Room lighting"; icon = "mdi:lightbulb-group"; show_in_sidebar = true;
      filename = pkgs.writeText "room-lighting-dashboard.yaml" (builtins.toJSON dashboard);
    };
  };
}
