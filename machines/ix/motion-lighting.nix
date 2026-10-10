# Motion and manual commands arbitrate through one queue, reading current state.
{ ... }:
let
  policy = import ./lighting-policy.nix;
  zones = policy.motionZones;
  ambient = import ./bathroom-ambient.nix { inherit policy; };
  # Matter reports quantized brightness/mireds. Tolerate rounding, not another
  # scene's brightness/color; otherwise our own reports could feed back forever.
  # Derive the rounded 0–255 target from the policy, so a percentage change
  # cannot leave feedback detection enforcing a stale brightness.
  needsOn = zone: lamp: if zone.turnOnData == { } then "${lamp}.state != 'on'" else ''
    (${lamp}.state != 'on'
     or ((${lamp}.attributes.get('brightness', 0) | int(0)) - (255 * ${ambient.percent} / 100) | round(0) | int) | abs > 2
     or ${lamp}.attributes.get('color_mode') != 'color_temp'
     or ((${lamp}.attributes.get('color_temp_kelvin', 0) | int(0)) - 2700) | abs > 25)
  '';
  priorityChoice = key:
    let zone = zones.${key}; in {
      conditions = "{{ room == '${key}' }}";
      sequence = (if zone ? ambient then [{ action = "script.lighting_bathroom_sample_ambient"; }] else []) ++ [{ choose = [
        {
          conditions = [
            { condition = "template"; value_template = "{{ can_activate | default(false) | bool }}"; }
            { condition = "state"; entity_id = zone.motion; state = "on"; }
            (if zone ? ambient then { condition = "template"; value_template = "${ambient.prelude} {{ ${ambient.valid} }}"; }
             else { condition = "numeric_state"; entity_id = zone.illuminance; below = zone.darkLux; })
            { condition = "template"; value_template = "{{ expand(${builtins.toJSON zone.lights}) | selectattr('entity_id', 'in', ${builtins.toJSON zone.lights}) | selectattr('state', 'in', ['on', 'off']) | rejectattr('attributes.entity_id', 'defined') | list | count > 0 }}"; }
          ];
          sequence = [
            { "if" = "{{ is_state('${zone.manual}', 'on') }}";
              "then" = [{ action = "input_boolean.turn_off"; target.entity_id = zone.manual; }]; }
            { "if" = "{{ not is_state('${zone.active}', 'on') }}";
              "then" = [{ action = "input_boolean.turn_on"; target.entity_id = zone.active; }]; }
            { variables.needed = ''
                ${if zone ? ambient then ambient.prelude else ""}
                {% set ns = namespace(lights=[]) %}
                {% for lamp in expand(${builtins.toJSON zone.lights}) %}
                  {% if lamp.entity_id in ${builtins.toJSON zone.lights}
                        and lamp.state in ['on', 'off']
                        and lamp.attributes.entity_id is not defined
                        and (force | default(false) | bool or ${needsOn zone "lamp"}) %}
                    {% set ns.lights = ns.lights + [lamp.entity_id] %}
                  {% endif %}
                {% endfor %}
                {{ ns.lights }}
              ''; }
            { condition = "template"; value_template = "{{ needed | count > 0 }}"; }
            ({ action = "light.turn_on"; target.entity_id = "{{ needed }}"; }
              // (if zone.turnOnData == { } then { } else {
                data = zone.turnOnData // { brightness_pct = "{{ ${ambient.percent} }}"; };
              }))
          ];
        }
        {
          conditions = [
            { condition = "template"; value_template = "{{ not is_state('${zone.manual}', 'on') }}"; }
            { condition = "state"; entity_id = zone.active; state = "on"; }
            { condition = "state"; entity_id = zone.motion; state = "off"; }
            { condition = "template"; value_template = "{{ (now() - states.${zone.motion}.last_changed).total_seconds() >= ${toString (zone.idleMinutes * 60)} }}"; }
          ];
          sequence = [
            { action = "light.turn_off"; target.entity_id = zone.lights; }
            # On failure ownership stays set, allowing the existing recovery.
            { action = "input_boolean.turn_off"; target.entity_id = zone.active; }
          ];
        }
      ]; }];
    };
  mkMotionAutomation = id: name: key:
    let zone = zones.${key}; in {
      inherit id;
      alias = name;
      description = "Low-light occupancy overrides manual/scenes; bathroom brightness is 20% midnight-07:00, otherwise 80% (local time). Lamp-off lux only gates activation. Clear for ${toString zone.idleMinutes} minutes before automatic off. Managed in Nix.";
      mode = "queued"; max = 5; initial_state = true;
      conditions = [
        { condition = "template"; value_template = "{{ trigger.id != 'resume' or trigger.event.data.get('room', 'all') in ['all', '${key}'] }}"; }
        # Only conflicting lamp reports need arbitration. Do not react to our
        # own already-correct reports, unrelated attributes, or unavailable lamps.
        { condition = "template"; value_template = ''
            ${if zone ? ambient then ambient.prelude else ""}
            {{ trigger.id != 'lamp' or
               (trigger.to_state is not none and trigger.from_state is not none
                and trigger.to_state.state in ['on', 'off']
                and (${needsOn zone "trigger.to_state"})) }}
          ''; }
      ];
      triggers = [
        { trigger = "state"; entity_id = zone.motion; to = "on"; id = "motion"; }
        { trigger = "numeric_state"; entity_id = zone.illuminance; below = zone.darkLux; id = "dark"; }
        { trigger = "state"; entity_id = zone.motion; to = "off"; "for".minutes = zone.idleMinutes; id = "idle"; }
        { trigger = "homeassistant"; event = "start"; id = "startup"; }
        { trigger = "event"; event_type = "ix_resume_automatic_lighting"; id = "resume"; }
        # Recover only vacancy deadlines, never periodically turn lamps on.
        { trigger = "time_pattern"; minutes = "/1"; id = "recovery"; }
        # Native scene/light calls can finish after their call_service listener.
        # Actual lamp reports close that race without polling or artificial waits.
        { trigger = "state"; entity_id = zone.lights; id = "lamp"; }
        { trigger = "state"; entity_id = zone.manual; to = "on"; id = "manual"; }
      ] ++ (if zone ? brightnessSchedule then [
        { trigger = "time"; at = [ "00:00:00" zone.brightnessSchedule.nightUntil ]; id = "schedule"; }
      ] else []);
      actions = [{
        action = "script.lighting_manual_action";
        data = { operation = "motion"; room = key; reason = "{{ trigger.id }}"; };
      }];
    };
in
{
  services.home-assistant.config = {
    # Restore ownership without putting these helpers in Recorder.
    input_boolean = {
      myggspray_lighting_active = { name = "MYGGSPRAY living room and kitchen lighting active"; icon = "mdi:motion-sensor"; };
      myggspray_bathroom_lighting_active = { name = "MYGGSPRAY bathroom night lighting active"; icon = "mdi:motion-sensor"; };
    };
    input_text.bathroom_lighting_ambient = {
      name = "Bathroom - Last lamp-off ambient sample";
      icon = "mdi:brightness-6";
      max = 255;
      # No initial: restore the last confirmed OFF sample across HA restarts.
    };
    script.lighting_bathroom_sample_ambient = {
      alias = "Lighting - Capture bathroom lamp-off illuminance";
      description = "Internal queue worker; never sample a lit lamp or an old lamp-on report.";
      mode = "queued"; max = 20;
      sequence = ambient.captureSequence;
    };
    "automation bathroom ambient" = [{
      id = "bathroom_capture_off_illuminance";
      alias = "Bathroom - Capture ambient light with lamp off";
      initial_state = true; mode = "queued"; max = 5;
      triggers = [
        { trigger = "state"; entity_id = zones.bathroom.illuminance; id = "lux_report"; }
        { trigger = "state"; entity_id = zones.bathroom.lights; to = "off";
          "for".seconds = zones.bathroom.ambient.settleSeconds; id = "settled_off"; }
        { trigger = "homeassistant"; event = "start"; id = "startup"; }
        # Same-value sensor reports need not fire state_changed. This observer
        # only acts on a NEW, timestamped OFF sample, never on a stale poll.
        { trigger = "time_pattern"; seconds = "/10"; id = "sample"; }
      ];
      conditions = [ { condition = "state"; entity_id = builtins.head zones.bathroom.lights; state = "off"; } ];
      actions = [{ action = "script.lighting_manual_action";
        data = { operation = "ambient"; room = "bathroom"; reason = "{{ trigger.id }}"; }; }];
    }];
    script.lighting_motion_priority = {
      alias = "Lighting - Reconcile motion priority";
      description = "Internal queue worker: current dark occupancy wins; vacancy timers remain unchanged.";
      mode = "queued"; max = 20;
      sequence = [
        { condition = "template"; value_template = "{{ room | default('') in ${builtins.toJSON (builtins.attrNames zones)} }}"; }
        { choose = builtins.map priorityChoice (builtins.attrNames zones); }
      ];
    };
    "automation myggspray" = [
      (mkMotionAutomation "myggspray_dark_living_kitchen_lights" "MYGGSPRAY - Living room and kitchen when dark" "living_kitchen")
      (mkMotionAutomation "myggspray_bathroom_night_light" "MYGGSPRAY - Bathroom night light" "bathroom")
    ];
  };
}
