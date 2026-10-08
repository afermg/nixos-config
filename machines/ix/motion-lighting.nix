# Nix-managed MYGGSPRAY lighting; HA restores ownership across restarts.
{ ... }:
let
  policy = import ./lighting-policy.nix;
  mkMotionAutomation =
    {
      id,
      name,
      motion,
      illuminance,
      active,
      manual,
      zone,
      lights,
      idleMinutes,
      darkLux ? 50,
      turnOnData ? { },
      preserveOnLights ? false,
    }:
    {
      inherit id;
      alias = name;
      description = "Turn on below ${toString darkLux} lux while occupied; turn off after ${toString idleMinutes} minutes continuously clear. Managed in Nix.";
      mode = "queued";
      max = 5;
      initial_state = true;
      # Remain enabled; only this zone's manual ownership gates its actions.
      conditions = [
        { condition = "template"; value_template = "{{ not is_state('${manual}', 'on') }}"; }
        { condition = "template"; value_template = "{{ trigger.id != 'resume' or trigger.event.data.get('room', 'all') in ['all', '${zone}'] }}"; }
      ];
      triggers = [
        {
          trigger = "state";
          entity_id = motion;
          to = "on";
          id = "motion";
        }
        {
          trigger = "numeric_state";
          entity_id = illuminance;
          below = darkLux;
          id = "dark";
        }
        {
          trigger = "state";
          entity_id = motion;
          to = "off";
          "for".minutes = idleMinutes;
          id = "idle";
        }
        {
          trigger = "homeassistant";
          event = "start";
          id = "startup";
        }
        {
          trigger = "event";
          event_type = "ix_resume_automatic_lighting";
          id = "resume";
        }
        {
          # HA resets state-trigger `for` timers on reload/restart. Recover
          # the deadline from the current uninterrupted clear state instead.
          trigger = "time_pattern";
          minutes = "/1";
          id = "recovery";
        }
      ];
      actions = [
        {
          choose = [
            {
              conditions = [
                {
                  condition = "trigger";
                  id = [
                    "motion"
                    "dark"
                    "startup"
                    "resume"
                  ];
                }
                {
                  condition = "state";
                  entity_id = motion;
                  state = "on";
                }
                {
                  # Invalid/missing lux fails closed; do not assume darkness.
                  condition = "numeric_state";
                  entity_id = illuminance;
                  below = darkLux;
                }
              ]
              ++ (
                if preserveOnLights then
                  [
                    {
                      # Do not dim/claim a bathroom light already on manually.
                      condition = "state";
                      entity_id = lights;
                      state = "off";
                    }
                  ]
                else
                  [ ]
              );
              sequence = [
                {
                  # Claim before the command so a partial failure can still be
                  # cleaned up after the room clears.
                  action = "input_boolean.turn_on";
                  target.entity_id = active;
                }
                (
                  {
                    action = "light.turn_on";
                    target.entity_id = lights;
                  }
                  // (if turnOnData == { } then { } else { data = turnOnData; })
                )
              ];
            }
            {
              conditions = [
                {
                  condition = "state";
                  entity_id = active;
                  state = "on";
                }
                {
                  # Unavailable motion is not evidence of vacancy.
                  condition = "state";
                  entity_id = motion;
                  state = "off";
                }
                {
                  condition = "template";
                  value_template = "{{ (now() - states.${motion}.last_changed).total_seconds() >= ${toString (idleMinutes * 60)} }}";
                }
              ];
              sequence = [
                {
                  action = "light.turn_off";
                  target.entity_id = lights;
                }
                {
                  # Retain ownership on command failure so recovery retries.
                  action = "input_boolean.turn_off";
                  target.entity_id = active;
                }
              ];
            }
          ];
        }
      ];
    };
in
{
  services.home-assistant.config = {
    # No initial values: restore ownership without adding helpers to Recorder.
    input_boolean = {
      myggspray_lighting_active = {
        name = "MYGGSPRAY living room and kitchen lighting active";
        icon = "mdi:motion-sensor";
      };
      myggspray_bathroom_lighting_active = {
        name = "MYGGSPRAY bathroom night lighting active";
        icon = "mdi:motion-sensor";
      };
    };

    "automation myggspray" = [
      (mkMotionAutomation {
        id = "myggspray_dark_living_kitchen_lights";
        name = "MYGGSPRAY - Living room and kitchen when dark";
        motion = "binary_sensor.myggspray_wrlss_mtn_sensor_occupancy";
        illuminance = "sensor.myggspray_wrlss_mtn_sensor_illuminance";
        inherit (policy.motionZones.living_kitchen) active manual lights;
        zone = "living_kitchen";
        idleMinutes = 10;
      })
      (mkMotionAutomation {
        id = "myggspray_bathroom_night_light";
        name = "MYGGSPRAY - Bathroom night light";
        # Bathroom MYGGSPRAY is now Matter node 21 (formerly 16). Fresh reads
        # confirmed these restored entity IDs; keep targets explicit.
        motion = "binary_sensor.myggspray_wrlss_mtn_sensor_occupancy_2";
        illuminance = "sensor.myggspray_wrlss_mtn_sensor_illuminance_2";
        inherit (policy.motionZones.bathroom) active manual lights;
        zone = "bathroom";
        idleMinutes = 5;
        preserveOnLights = true;
        turnOnData = {
          brightness_pct = 10;
          color_temp_kelvin = 2700;
        };
      })
    ];
  };
}
