# Four explicitly bound BILRESA remotes; only all-off crosses control groups.
{ ... }:
let
  policy = import ./lighting-policy.nix;
  lights = policy.lights;
  zones = policy.motionZones;
  ambient = import ./bathroom-ambient.nix { inherit policy; };
  remoteRooms = builtins.listToAttrs (builtins.concatMap (room:
    builtins.map (name: { inherit name; value = room; })
      (policy.bilresa.${room}.top ++ policy.bilresa.${room}.bottom)
  ) (builtins.attrNames policy.bilresa));
  scopedAllowed = ''
    {% set allowed = ${builtins.toJSON lights} %}
    {% set selected = room | default('all') %}
    {% set areas = ${builtins.toJSON policy.roomAreas} %}
    {% set scope = namespace(members=[]) %}
    {% for area in areas.get(selected, []) %}
      {% set scope.members = scope.members + area_entities(area) %}
    {% endfor %}
    {% if selected != 'all' %}{% set allowed = allowed | select('in', scope.members) | list %}{% endif %}
  '';
  pauseZone = zone: {
    choose = [{
      conditions = ''
        {{ affected_lights | select('in', ${builtins.toJSON zone.lights}) | list | count > 0
           and not (temporary_only | default(false) | bool)
           and (not is_state('${zone.mode}', 'Manual') or not is_state('${zone.manual}', 'on') or not is_state('${zone.active}', 'off')) }}
      '';
      # Deliberate manual commands latch the mode; automatic reports never do.
      # All off has separate temporary bookkeeping and must preserve this mode.
      sequence = [
        { "if" = "{{ not is_state('${zone.mode}', 'Manual') }}";
          "then" = [{ action = "input_select.select_option";
            target.entity_id = zone.mode; data.option = "Manual"; }]; }
        { action = "input_boolean.turn_on"; target.entity_id = zone.manual; }
        { action = "input_boolean.turn_off"; target.entity_id = zone.active; }
      ];
    }];
  };
  nativeTargets = ''
    {% set data = trigger.event.data.get('service_data', {}) %}
    {% set ids = data.get('entity_id', []) %}
    {% set ns = namespace(ids=[ids] if ids is string else ids) %}
    {% for field in ['area_id', 'device_id', 'label_id'] %}
      {% set values = data.get(field, []) %}
      {% for value in ([values] if values is string else values) %}
        {% if field == 'area_id' %}{% set ns.ids = ns.ids + area_entities(value) %}
        {% elif field == 'device_id' %}{% set ns.ids = ns.ids + device_entities(value) %}
        {% else %}
          {% set ns.ids = ns.ids + label_entities(value) %}
          {% for area in label_areas(value) %}{% set ns.ids = ns.ids + area_entities(area) %}{% endfor %}
          {% for device in label_devices(value) %}{% set ns.ids = ns.ids + device_entities(device) %}{% endfor %}
        {% endif %}
      {% endfor %}
    {% endfor %}
    {% set allowed = ${builtins.toJSON lights} %}
    {{ allowed if 'all' in ns.ids else allowed | select('in', ns.ids) | list }}
  '';
  sceneSafe = ''
    {% set members = state_attr(scene_entity | default(""), 'entity_id') or [] %}
    ${scopedAllowed}
    {{ scene_entity is defined and scene_entity.startswith('scene.')
       and states(scene_entity) != 'unavailable' and members | count > 0
       and members | reject('in', allowed) | list | count == 0
       and expand(members) | selectattr('attributes.entity_id', 'defined') | list | count == 0 }}
  '';
  dispatch = operation: data: {
    action = "script.lighting_manual_action";
    data = { inherit operation; } // data;
  };
  sceneCandidates = ''
    {% set ns = namespace(scenes=[]) %}
    ${scopedAllowed}
    {% for entity in ${builtins.toJSON policy.sceneCycles}.get(room | default(""), []) %}
      {% set members = state_attr(entity, 'entity_id') or [] %}
      {% if entity.startswith('scene.') and states(entity) != 'unavailable'
            and members | count > 0
            and members | reject('in', allowed) | list | count == 0
            and expand(members) | selectattr('attributes.entity_id', 'defined') | list | count == 0 %}
        {% set ns.scenes = ns.scenes + [entity] %}
      {% endif %}
    {% endfor %}
    {{ ns.scenes }}
  '';
in
{
  services.home-assistant.config = {
    input_boolean = {
      # Retain the former helper's identity, but never gate motion with it.
      lighting_manual_override = { name = "Lighting - Legacy global override (unused)"; icon = "mdi:history"; };
    } // builtins.listToAttrs (builtins.map (zone: {
      name = builtins.replaceStrings [ "input_boolean." ] [ "" ] zone.manual;
      value = { name = "${zone.name} - Manual ownership"; icon = "mdi:hand-back-right"; };
      # No initial values: restore each area's manual ownership independently.
    }) (builtins.attrValues zones)) // builtins.listToAttrs (builtins.map (zone: {
      name = builtins.replaceStrings [ "input_boolean." ] [ "" ] zone.offHold;
      value = { name = "${zone.name} - Motion paused by All off"; icon = "mdi:motion-sensor-off"; };
      # Temporary All off bookkeeping is independent of the persistent mode.
    }) (builtins.attrValues zones));
    input_select = builtins.listToAttrs (builtins.map (zone: {
      name = builtins.replaceStrings [ "input_select." ] [ "" ] zone.mode;
      value = { name = "${zone.name} - Lighting mode";
        options = [ "Automatic" "Manual" ]; icon = "mdi:lightbulb-auto"; };
      # No initial: restore Manual across restarts; new helpers default Automatic.
    }) (builtins.attrValues zones));
    "automation lighting mode" = builtins.map (key: let zone = zones.${key}; in {
      id = "lighting_mode_${key}"; alias = "${zone.name} - Apply lighting mode";
      initial_state = true; mode = "queued"; max = 5;
      triggers = [
        { trigger = "state"; entity_id = zone.mode; to = "Automatic"; }
        { trigger = "state"; entity_id = zone.mode; to = "Manual"; }
        { trigger = "homeassistant"; event = "start"; }
        { trigger = "event"; event_type = "automation_reloaded"; }
      ];
      conditions = [];
      actions = [{ action = "script.lighting_manual_action";
        data = { operation = "mode_changed"; room = key; }; }];
    }) (builtins.attrNames zones);
    timer = builtins.listToAttrs (builtins.map (zone: {
      name = builtins.replaceStrings [ "timer." ] [ "" ] zone.offTimer;
      value = { name = "${zone.name} - All off motion pause";
        duration = "00:00:30"; restore = true; icon = "mdi:timer-sand"; };
    }) (builtins.attrValues zones));
    # Idle also covers cancellation and an expiry while HA was stopped. Reload
    # reconciliation prevents a missed event from leaving stale ownership behind.
    "automation lighting all off expiry" = builtins.map (key: let zone = zones.${key}; in {
      id = "lighting_all_off_expiry_${key}";
      alias = "${zone.name} - Resume motion after All off";
      initial_state = true; mode = "queued"; max = 5;
      triggers = [
        { trigger = "state"; entity_id = zone.offTimer; to = "idle"; }
        { trigger = "homeassistant"; event = "start"; }
        { trigger = "event"; event_type = "automation_reloaded"; }
      ];
      conditions = [
        { condition = "state"; entity_id = zone.offTimer; state = "idle"; }
        { condition = "state"; entity_id = zone.offHold; state = "on"; }
      ];
      actions = [{ action = "script.lighting_manual_action";
        data = { operation = "expire_all_off"; room = key; }; }];
    }) (builtins.attrNames zones);
    script = {
      lighting_take_manual_control = {
        alias = "Lighting - Take manual control";
        mode = "queued";
        max = 20;
        sequence = [
          { condition = "template"; value_template = "{{ affected_lights is defined and affected_lights is not string and affected_lights | count > 0 and affected_lights | reject('in', ${builtins.toJSON lights}) | list | count == 0 }}"; }
          { "if" = "{{ affected_lights | select('in', ${builtins.toJSON zones.bathroom.lights}) | list | count > 0 }}";
            "then" = [{ action = "script.lighting_bathroom_sample_ambient"; }]; }
        ] ++ builtins.map pauseZone (builtins.attrValues zones);
      };
      # One queue serializes mode, scene-cycle, manual and motion actions.
      # Post-command arbitration respects Manual even if occupancy changes.
      lighting_manual_action = {
        alias = "Lighting - Serialized manual action";
        mode = "queued";
        max = 20;
        sequence = [
          { condition = "template"; value_template = "{{ operation | default('') in ['scene', 'cycle', 'brightness', 'level', 'temperature', 'all_off', 'room_on', 'room_off', 'resume', 'toggle_mode', 'mode_changed', 'expire_all_off', 'takeover', 'motion', 'ambient'] }}"; }
          { condition = "template"; value_template = "{{ operation not in ['room_on', 'room_off', 'brightness', 'level', 'resume', 'toggle_mode', 'mode_changed', 'expire_all_off', 'motion', 'scene'] or room | default('all') in ${builtins.toJSON ((builtins.attrNames policy.roomAreas) ++ [ "all" ])} }}"; }
          { condition = "template"; value_template = "{{ operation != 'ambient' or room | default('') == 'bathroom' }}"; }
          { condition = "template"; value_template = "{{ operation != 'cycle' or (room | default('') in ${builtins.toJSON (builtins.attrNames policy.sceneCycles)} and direction | default('next') in ['next', 'previous']) }}"; }
          { condition = "template"; value_template = "{{ operation != 'temperature' or room | default('') in ${builtins.toJSON policy.rooms} }}"; }
          { condition = "template"; value_template = "{{ operation != 'temperature' or (is_number(kelvin | default(none)) and 2202 <= kelvin | float <= 6535) }}"; }
          { condition = "template"; value_template = "{{ operation != 'brightness' or (is_number(scale | default(none)) and 0 < scale | float(0) <= 2) }}"; }
          { condition = "template"; value_template = "{{ operation != 'level' or (is_number(level | default(none)) and 0 <= level | float(0) <= 255) }}"; }
          { condition = "template"; value_template = "{{ operation != 'takeover' or (affected_lights is defined and affected_lights is not string and affected_lights | reject('in', ${builtins.toJSON lights}) | list | count == 0) }}"; }
          { condition = "template"; value_template = ''
              {% if operation == 'scene' %}${sceneSafe}{% else %}{{ true }}{% endif %}
            ''; }
          { variables.targets = ''
              {% set allowed = ${builtins.toJSON lights} %}
              {% set selected = room | default('all') %}
              {% set room_areas = ${builtins.toJSON policy.roomAreas} %}
              {% set ns = namespace(members=[]) %}
              {% for area in room_areas.get(selected, []) %}
                {% set ns.members = ns.members + area_entities(area) %}
              {% endfor %}
              {{ allowed if selected == 'all'
                 else allowed | select('in', ns.members) | list }}
            ''; }
          { variables.lit = ''
              {% set ns = namespace(lights=[]) %}
              {% for light in expand(targets) %}
                {% set brightness = light.attributes.get('brightness', 0) | int(0) %}
                {% if light.entity_id in targets and light.state == 'on' and brightness > 0 and light.attributes.entity_id is not defined %}
                  {% set ns.lights = ns.lights + [{'entity_id': light.entity_id, 'brightness': brightness}] %}
                {% endif %}
              {% endfor %}
              {{ ns.lights }}
            ''; }
          { variables.available_targets = ''
              {{ expand(targets) | selectattr('entity_id', 'in', targets)
                 | selectattr('state', 'in', ['on', 'off'])
                 | rejectattr('attributes.entity_id', 'defined')
                 | map(attribute='entity_id') | list }}
            ''; }
          {
            choose = [{
              conditions = "{{ operation == 'cycle' }}";
              sequence = [{ action = "script.lighting_cycle_group";
                data = { room = "{{ room }}"; direction = "{{ direction | default('next') }}"; }; }];
            } {
              conditions = "{{ operation in ['toggle_mode', 'mode_changed'] }}";
              sequence = builtins.map (key: let zone = zones.${key}; in {
                choose = [{
                  conditions = "{{ room == '${key}' or (room in ['living_room', 'kitchen'] and '${key}' == 'living_kitchen') }}";
                  sequence = [{ choose = [{
                    conditions = "{{ operation == 'toggle_mode' and states('${zone.mode}') in ['Automatic', 'Manual'] }}";
                    sequence = [{ action = "input_select.select_option"; target.entity_id = zone.mode;
                      data.option = "{{ 'Automatic' if is_state('${zone.mode}', 'Manual') else 'Manual' }}"; }];
                  } {
                    conditions = "{{ operation == 'mode_changed' and is_state('${zone.mode}', 'Manual') }}";
                    sequence = [
                      { "if" = "{{ not is_state('${zone.manual}', 'on') }}";
                        "then" = [{ action = "input_boolean.turn_on"; target.entity_id = zone.manual; }]; }
                      { "if" = "{{ not is_state('${zone.active}', 'off') }}";
                        "then" = [{ action = "input_boolean.turn_off"; target.entity_id = zone.active; }]; }
                    ];
                  } {
                    conditions = "{{ operation == 'mode_changed' and is_state('${zone.mode}', 'Automatic') }}";
                    sequence = [
                      { action = "input_boolean.turn_off"; target.entity_id = zone.manual; }
                      { event = "ix_resume_automatic_lighting"; event_data.room = key; }
                    ];
                  }]; }];
                }];
              }) (builtins.attrNames zones);
            } {
              conditions = "{{ operation == 'expire_all_off' }}";
              sequence = builtins.map (key: let zone = zones.${key}; in {
                choose = [{
                  # Recheck inside the shared queue: an older expiry must never
                  # clear a fresh 30-second pause from a subsequent All off.
                  conditions = "{{ room == '${key}' and is_state('${zone.offTimer}', 'idle') and is_state('${zone.offHold}', 'on') }}";
                  sequence = [
                    { action = "input_boolean.turn_off"; target.entity_id = [ zone.offHold zone.manual ]; }
                    { event = "ix_resume_automatic_lighting"; event_data.room = key; }
                  ];
                }];
              }) (builtins.attrNames zones);
            } {
              conditions = "{{ operation == 'resume' }}";
              sequence = [
                { variables.resume_rooms = ''
                    {% set selected = room | default('all') %}
                    {{ ${builtins.toJSON (builtins.attrNames zones)} if selected == 'all'
                       else ['living_kitchen'] if selected in ['living_room', 'kitchen'] else [selected] }}
                  ''; }
                { action = "input_boolean.turn_off"; target.entity_id = "input_boolean.lighting_manual_override"; }
              ] ++ builtins.map (key: let zone = zones.${key}; in {
                choose = [{
                  conditions = "{{ '${key}' in resume_rooms }}";
                  sequence = [
                    { action = "input_boolean.turn_off"; target.entity_id = [ zone.offHold zone.manual ]; }
                    { action = "timer.cancel"; target.entity_id = zone.offTimer; }
                    { action = "input_select.select_option"; target.entity_id = zone.mode; data.option = "Automatic"; }
                    { action = "automation.turn_on"; target.entity_id = zone.automation; }
                    { event = "ix_resume_automatic_lighting"; event_data.room = key; }
                  ];
                }];
              }) (builtins.attrNames zones);
            } {
              conditions = "{{ operation == 'ambient' }}";
              sequence = [
                { variables.previous_ambient = "{{ states('${zones.bathroom.ambient.helper}') }}"; }
                # Initial integration states can come from the Matter cache.
                # Require a subsequent report, but preserve any known OFF sample.
                { "if" = "{{ reason | default('') == 'startup' }}";
                  "then" = [{ action = "input_text.set_value";
                    target.entity_id = zones.bathroom.ambient.helper;
                    data.value = ''
                      ${ambient.prelude}
                      ambient:{{ {'lux': ambient.get('lux') if ambient is mapping else none,
                                  'sampled': ambient.get('sampled') if ambient is mapping else none,
                                  'started': as_timestamp(now())} | to_json }}
                    '';
                  }]; }
                { action = "script.lighting_bathroom_sample_ambient"; }
                { condition = "template"; value_template = "{{ states('${zones.bathroom.ambient.helper}') != previous_ambient }}"; }
                { action = "script.lighting_motion_priority";
                  data = { room = "bathroom"; can_activate = true; }; }
              ];
            } {
              conditions = "{{ operation == 'motion' }}";
              sequence = [{
                action = "script.lighting_motion_priority";
                data = { room = "{{ room }}"; can_activate = "{{ reason | default('') not in ['idle', 'recovery'] }}"; };
              }];
            }];
            default = [
              { variables.manual_targets = ''
                  {{ state_attr(scene_entity, 'entity_id') if operation == 'scene'
                     else affected_lights if operation == 'takeover'
                     else ${builtins.toJSON lights} if operation == 'all_off'
                     else available_targets if operation == 'level' and (level | float == 0 or lit | count == 0)
                     else (lit | map(attribute='entity_id') | list if lit | count > 0 else available_targets) if operation == 'temperature'
                     else lit | map(attribute='entity_id') | list if operation in ['brightness', 'level']
                     else targets }}
                ''; }
              { condition = "template"; value_template = "{{ manual_targets | count > 0 }}"; }
              { action = "script.lighting_take_manual_control";
                data = { affected_lights = "{{ manual_targets }}"; temporary_only = "{{ operation == 'all_off' }}"; }; }
              {
                choose = [
                  {
                    # Native UI commands can race an already queued/in-flight
                    # automatic write. Reapply an absolute user brightness only
                    # AFTER latching Manual, in the same arbitration queue.
                    conditions = "{{ operation == 'takeover' and requested | default({}) | count > 0 }}";
                    sequence = [{ action = "light.turn_on"; target.entity_id = "{{ manual_targets }}";
                      data = "{{ requested }}"; }];
                  }
                  {
                    conditions = "{{ operation == 'takeover' and native_scenes | default([]) | count > 0 }}";
                    sequence = [{ action = "scene.turn_on"; target.entity_id = "{{ native_scenes }}"; }];
                  }
                  {
                    conditions = "{{ operation == 'scene' }}";
                    sequence = [{ action = "scene.turn_on"; target.entity_id = "{{ scene_entity }}"; }];
                  }
                  {
                    conditions = "{{ operation == 'temperature' }}";
                    sequence = [{ action = "light.turn_on"; target.entity_id = "{{ manual_targets }}";
                      data.color_temp_kelvin = "{{ kelvin | int }}"; }];
                  }
                  {
                    conditions = "{{ operation == 'all_off' }}";
                    # Start/restart a bounded pause before any lamp command.
                    # No blocking delay: manual controls keep using the queue.
                    sequence = [
                      { action = "timer.start";
                        target.entity_id = builtins.map (zone: zone.offTimer) (builtins.attrValues zones);
                        data.duration = "00:00:30"; }
                      { action = "input_boolean.turn_on";
                        target.entity_id = builtins.concatMap (zone: [ zone.offHold zone.manual ]) (builtins.attrValues zones); }
                      { action = "input_boolean.turn_off";
                        target.entity_id = builtins.map (zone: zone.active) (builtins.attrValues zones); }
                      { action = "light.turn_off"; target.entity_id = lights; }
                    ];
                  }
                  {
                    conditions = "{{ operation in ['room_on', 'room_off'] and targets | count > 0 }}";
                    sequence = [{ action = "{{ 'light.turn_on' if operation == 'room_on' else 'light.turn_off' }}"; target.entity_id = "{{ targets }}"; }];
                  }
                  {
                    conditions = "{{ operation == 'level' and level | float == 0 }}";
                    sequence = [{ action = "light.turn_off"; target.entity_id = "{{ manual_targets }}"; }];
                  }
                  {
                    conditions = "{{ operation == 'level' and lit | count == 0 }}";
                    sequence = [{ action = "light.turn_on"; target.entity_id = "{{ manual_targets }}";
                      data.brightness = "{{ [1, level | float | round(0) | int] | max }}"; }];
                  }
                  {
                    conditions = "{{ operation in ['brightness', 'level'] }}";
                    sequence = [
                      { variables.gain = "{{ level | float / (lit | map(attribute='brightness') | max) if operation == 'level' else [scale | float, 255.0 / (lit | map(attribute='brightness') | max)] | min }}"; }
                      { variables.shared_level = "{{ [1, ((lit | map(attribute='brightness') | max) * gain) | round(0) | int] | max }}"; }
                      { repeat = {
                          for_each = "{{ lit }}";
                          sequence = [{
                            action = "light.turn_on";
                            target.entity_id = "{{ repeat.item.entity_id }}";
                            data.brightness = "{{ shared_level if room | default('all') == 'living_kitchen' else [1, (repeat.item.brightness * gain) | round(0) | int] | max }}";
                          }];
                        }; }
                    ];
                  }
                ];
              }
              # Never turn a temporary All off into a persistent manual hold.
              { action = "script.lighting_take_manual_control";
                data = { affected_lights = "{{ manual_targets }}"; temporary_only = "{{ operation == 'all_off' }}"; }; }
            ] ++ builtins.map (key: let zone = zones.${key}; in {
              choose = [{
                conditions = "{{ manual_targets | select('in', ${builtins.toJSON zone.lights}) | list | count > 0 }}";
                sequence = [{
                  action = "script.lighting_motion_priority";
                  data = { room = key; can_activate = true; force = true; };
                }];
              }];
            }) (builtins.attrNames zones);
          }
        ];
      };
      lighting_toggle_automatic = {
        alias = "Lighting - Toggle Automatic or Manual";
        description = "Only the selected motion zone; bedroom has no motion mode. Preserve any All off countdown.";
        mode = "queued";
        fields.room = { required = true; selector.select.options = policy.rooms; };
        sequence = [ (dispatch "toggle_mode" { room = "{{ room }}"; }) ];
      };
      lighting_resume_automatic = {
        alias = "Lighting - Resume automatic lighting";
        icon = "mdi:motion-sensor";
        mode = "queued";
        fields.room = { name = "Area (omit for all)"; default = "all"; selector.select.options = policy.rooms ++ [ "all" ]; };
        sequence = [ (dispatch "resume" { room = "{{ room | default('all') }}"; }) ];
      };
      lighting_activate_scene = {
        alias = "Lighting - Select manual scene";
        mode = "queued";
        fields.scene_entity = {
          name = "Lighting scene"; required = true; selector.entity.domain = "scene";
        };
        sequence = [ (dispatch "scene" { scene_entity = "{{ scene_entity }}"; }) ];
      };
      bilresa_cycle_scenes = {
        alias = "BILRESA - Cycle button scenes";
        description = "Serialized Off / Medium / Full cycle, strictly inside the selected group.";
        mode = "queued";
        sequence = [ (dispatch "cycle" { room = "{{ room | default('') }}"; direction = "{{ direction | default('next') }}"; }) ];
      };
      lighting_cycle_group = {
        alias = "Lighting - Internal group scene cycle";
        description = "Queue worker: validate both editable presets before any command; Off is scoped and enters Manual.";
        mode = "queued";
        fields.direction = {
          name = "Direction"; default = "next";
          selector.select.options = [ "next" "previous" ];
        };
        sequence = [
          { condition = "template"; value_template = "{{ direction | default('next') in ['next', 'previous'] and room | default('') in ${builtins.toJSON (builtins.attrNames policy.sceneCycles)} }}"; }
          { variables.scene_ids = sceneCandidates; }
          { condition = "template"; value_template = "{{ scene_ids | count == 2 }}"; }
          { variables.cycle_targets = ''
              ${scopedAllowed}
              {{ allowed }}
            ''; }
          { condition = "template"; value_template = "{{ cycle_targets | count > 0 and expand(cycle_targets) | selectattr('state', 'in', ['on', 'off']) | list | count == cycle_targets | count }}"; }
          { variables.next_scene = ''
              {% set ns = namespace(latest=0, index=0) %}
              {% for entity in scene_ids %}
                {% set activated = as_timestamp(states(entity), 0) %}
                {% if activated > ns.latest %}
                  {% set ns.latest = activated %}{% set ns.index = loop.index %}
                {% endif %}
              {% endfor %}
              {% if expand(cycle_targets) | selectattr('state', 'eq', 'on') | list | count == 0 %}{% set ns.index = 0 %}{% endif %}
              {% set step = -1 if direction | default('next') == 'previous' else 1 %}
              {{ (['off'] + scene_ids)[(ns.index + step) % 3] }}
            ''; }
          { action = "script.lighting_take_manual_control"; data.affected_lights = "{{ cycle_targets }}"; }
          { choose = [{ conditions = "{{ next_scene == 'off' }}";
              sequence = [{ action = "light.turn_off"; target.entity_id = "{{ cycle_targets }}"; }]; }];
            default = [{ action = "scene.turn_on"; target.entity_id = "{{ next_scene }}"; }]; }
        ];
      };
      bilresa_adjust_lights = {
        alias = "BILRESA - Scoped brightness";
        description = "Only the selected group. Living/kitchen lit lamps receive one equal level; bedroom lamps preserve balance. Bathroom is independent. Off bulbs remain off.";
        mode = "queued";
        fields.scale = { name = "Brightness multiplier"; required = true; selector.number = { min = 0.1; max = 2; step = 0.05; mode = "box"; }; };
        sequence = [ (dispatch "brightness" { room = "{{ room | default('all') }}"; scale = "{{ scale }}"; }) ];
      };
      bilresa_all_lights_off = {
        alias = "BILRESA - All lights off";
        description = "Turn off all six lamps and pause motion for 30 seconds. Another All off restarts the countdown; persistent Manual modes are unchanged.";
        icon = "mdi:lightbulb-group-off";
        mode = "queued";
        sequence = [ (dispatch "all_off" { }) ];
      };
    };
    "automation bilresa" = [
      {
        id = "bilresa_manual_lighting";
        initial_state = true;
        alias = "BILRESA - Manual lighting controls";
        description = "1/2: bedroom only; 3/4: living+kitchen at equal brightness. Short adjusts the group and enters Manual; double cycles Off/Medium/Full; top long toggles its motion mode (bedroom has none). Bottom long is global all-off with a 30-second motion pause, restarted by another All off.";
        mode = "queued";
        max = 20;
        triggers = [
          { trigger = "state"; entity_id = builtins.concatMap (group: group.top) (builtins.attrValues policy.bilresa); id = "top"; }
          { trigger = "state"; entity_id = builtins.concatMap (group: group.bottom) (builtins.attrValues policy.bilresa); id = "bottom"; }
        ];
        conditions = [{ condition = "template"; value_template = ''
          {{ trigger.from_state is not none and trigger.to_state is not none
             and trigger.to_state.state not in ['unknown', 'unavailable']
             and not trigger.to_state.attributes.get('restored', false)
             and trigger.to_state.state != trigger.from_state.state
             and trigger.to_state.attributes.get('event_type') in ['multi_press_1', 'multi_press_2', 'long_press']
             and (as_timestamp(trigger.to_state.state, 0) - as_timestamp(trigger.to_state.last_changed)) | abs < 5
             and (as_timestamp(now()) - as_timestamp(trigger.to_state.state, 0)) | abs < 5 }}
        ''; }];
        actions = [
          { variables.remote_room = "{{ ${builtins.toJSON remoteRooms}.get(trigger.to_state.entity_id, '') }}"; }
          { condition = "template"; value_template = "{{ remote_room in ${builtins.toJSON (builtins.attrNames policy.bilresa)} }}"; }
          { choose = [
          { conditions = "{{ trigger.id == 'top' and trigger.to_state.attributes.event_type == 'multi_press_1' }}";
            sequence = [{ action = "script.bilresa_adjust_lights"; data = { room = "{{ remote_room }}"; scale = 1.25; }; }]; }
          { conditions = "{{ trigger.id == 'bottom' and trigger.to_state.attributes.event_type == 'multi_press_1' }}";
            sequence = [{ action = "script.bilresa_adjust_lights"; data = { room = "{{ remote_room }}"; scale = 0.8; }; }]; }
          { conditions = "{{ trigger.id == 'top' and trigger.to_state.attributes.event_type == 'multi_press_2' }}";
            sequence = [{ action = "script.bilresa_cycle_scenes"; data = { room = "{{ remote_room }}"; direction = "next"; }; }]; }
          { conditions = "{{ trigger.id == 'bottom' and trigger.to_state.attributes.event_type == 'multi_press_2' }}";
            sequence = [{ action = "script.bilresa_cycle_scenes"; data = { room = "{{ remote_room }}"; direction = "previous"; }; }]; }
          { conditions = "{{ trigger.id == 'top' and trigger.to_state.attributes.event_type == 'long_press' }}";
            sequence = [{ action = "script.lighting_toggle_automatic"; data.room = "{{ remote_room }}"; }]; }
          { conditions = "{{ trigger.id == 'bottom' and trigger.to_state.attributes.event_type == 'long_press' }}";
            sequence = [{ action = "script.bilresa_all_lights_off"; }]; }
        ]; }];
      }
      {
        id = "lighting_native_scene_manual_override";
        initial_state = true;
        alias = "Lighting - Pause motion for a UI lighting scene";
        description = "Human-selected native scenes take manual ownership. Ignore automated and wrapped calls.";
        mode = "queued";
        triggers = [{
          trigger = "event"; event_type = "call_service";
          event_data = { domain = "scene"; service = "turn_on"; };
        }];
        conditions = [{ condition = "template"; value_template = ''
          {% set ids = trigger.event.data.get('service_data', {}).get('entity_id', []) %}
          {% set ids = [ids] if ids is string else ids %}
          {% set ns = namespace(safe=ids | count > 0) %}
          {% for entity in ids %}
            {% set members = state_attr(entity, 'entity_id') or [] %}
            {% if not entity.startswith('scene.') or members | count == 0
                  or members | reject('in', ${builtins.toJSON lights}) | list | count > 0
                  or expand(members) | selectattr('attributes.entity_id', 'defined') | list | count > 0 %}
              {% set ns.safe = false %}
            {% endif %}
          {% endfor %}
          {{ ns.safe and trigger.event.context.user_id is not none and trigger.event.context.parent_id is none }}
        ''; }];
        actions = [{
          action = "script.lighting_manual_action";
          data = {
            operation = "takeover";
            native_scenes = ''
              {% set ids = trigger.event.data.get('service_data', {}).get('entity_id', []) %}
              {{ [ids] if ids is string else ids }}
            '';
            affected_lights = ''
              {% set ids = trigger.event.data.get('service_data', {}).get('entity_id', []) %}
              {% set ns = namespace(members=[]) %}
              {% for entity in ([ids] if ids is string else ids) %}
                {% set ns.members = ns.members + (state_attr(entity, 'entity_id') or []) %}
              {% endfor %}
              {{ ns.members | unique | list }}
            '';
          };
        }];
      }
      {
        id = "lighting_native_light_manual_override";
        alias = "Lighting - Room ownership for direct manual lamp controls";
        initial_state = true;
        mode = "queued";
        max = 20;
        triggers = builtins.map (service: {
          trigger = "event"; event_type = "call_service";
          event_data = { domain = "light"; inherit service; };
        }) [ "turn_on" "turn_off" "toggle" ];
        # Automatic lighting has no human user context. Never feed its own
        # service calls back into manual ownership. Wrapped controls pause first.
        conditions = [{ condition = "template"; value_template = "{{ trigger.event.context.user_id is not none and trigger.event.context.parent_id is none }}"; }];
        actions = [{
          action = "script.lighting_manual_action";
          data = { operation = "takeover"; affected_lights = nativeTargets;
            requested = ''
              {% set data = trigger.event.data.get('service_data', {}) %}
              {% set ns = namespace(data={}) %}
              {% if trigger.event.data.get('service') == 'turn_on' and ('brightness' in data or 'brightness_pct' in data) %}
                {% for key in ['brightness', 'brightness_pct', 'color_temp_kelvin', 'color_temp', 'hs_color', 'xy_color', 'rgb_color', 'transition'] %}
                  {% if key in data %}{% set ns.data = dict(ns.data, **{key: data[key]}) %}{% endif %}
                {% endfor %}
              {% endif %}
              {{ ns.data }}
            '';
          };
        }];
      }
    ];
  };
}
