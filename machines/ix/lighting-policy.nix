# Explicit lamp allowlist: never include appliance plugs or infrastructure.
{
  lights = [
    "light.bedroom_matter_device"
    "light.bedroom_kajplats_1100lm"
    "light.kajplats_e26_ws_globe_1600lm"
    "light.living_room_kajplats_e26_living_room_1100lm"
    "light.kitchen_kajplats_e26_kitchen_1100lm"
    "light.bathroom_kajplats_e26_1100lm_bathroom_2"
  ];
  # Match actual motion targets, not scene names: an explicit OFF is manual too.
  motionZones = {
    living_kitchen = {
      name = "Living room + kitchen";
      mode = "input_select.lighting_mode_living_kitchen";
      manual = "input_boolean.lighting_manual_living_kitchen";
      offHold = "input_boolean.lighting_all_off_hold_living_kitchen";
      offTimer = "timer.lighting_all_off_pause_living_kitchen";
      offPauseSeconds = 30;
      automation = "automation.myggspray_living_room_and_kitchen_when_dark";
      active = "input_boolean.myggspray_lighting_active";
      motion = "binary_sensor.myggspray_wrlss_mtn_sensor_occupancy";
      illuminance = "sensor.myggspray_wrlss_mtn_sensor_illuminance";
      # Fresh lamp-off calibration: 42 lx was already bright enough (2026-10-09).
      # Exclude that level with a small margin; activate only strictly below 40.
      darkLux = 40;
      idleMinutes = 10;
      turnOnData = { };
      lights = [
        "light.kajplats_e26_ws_globe_1600lm"
        "light.living_room_kajplats_e26_living_room_1100lm"
        "light.kitchen_kajplats_e26_kitchen_1100lm"
      ];
    };
    bathroom = {
      name = "Bathroom";
      mode = "input_select.lighting_mode_bathroom";
      manual = "input_boolean.lighting_manual_bathroom";
      offHold = "input_boolean.lighting_all_off_hold_bathroom";
      offTimer = "timer.lighting_all_off_pause_bathroom";
      offPauseSeconds = 5;
      automation = "automation.myggspray_bathroom_night_light";
      active = "input_boolean.myggspray_bathroom_lighting_active";
      motion = "binary_sensor.myggspray_wrlss_mtn_sensor_occupancy_2";
      illuminance = "sensor.myggspray_wrlss_mtn_sensor_illuminance_2";
      darkLux = 50;
      idleMinutes = 5;
      # OFF-era ambient lux gates activation only, never brightness selection.
      brightnessSchedule = {
        nightUntil = "07:00:00"; # Midnight inclusive through 06:59:59, HA local time.
        nightBrightnessPct = 20;
        dayBrightnessPct = 80;
      };
      ambient = {
        helper = "input_text.bathroom_lighting_ambient";
        settleSeconds = 2;
        maxAgeSeconds = 1800;
      };
      turnOnData = { brightness_pct = 20; color_temp_kelvin = 2700; };
      lights = [ "light.bathroom_kajplats_e26_1100lm_bathroom_2" ];
    };
  };
  rooms = [ "bedroom" "living_kitchen" "bathroom" ];
  # Ordered, editable presets. The Off stage is a scoped command, not a scene.
  sceneCycles = {
    bedroom = [ "scene.bedroom_medium_illumination" "scene.bedroom_full_illumination" ];
    living_kitchen = [
      "scene.living_kitchen_medium_illumination"
      "scene.living_kitchen_full_illumination"
      "scene.living_room_only_mid"
      "scene.living_room_only_high"
    ];
  };
  # Exact registered remotes: 1/2 bedroom only, 3/4 living+kitchen.
  # No area-name/device discovery can accidentally bind another remote.
  bilresa = {
    bedroom = {
      top = [ "event.bedroom_bilresa_dual_button_1_button_1" "event.bilresa_dual_button_button_1" ];
      bottom = [ "event.bedroom_bilresa_dual_button_1_button_2" "event.bilresa_dual_button_button_2" ];
    };
    living_kitchen = {
      top = [ "event.living_room_bilresa_dual_button_3_button_1" "event.bilresa_dual_button_button_1_2" ];
      bottom = [ "event.living_room_bilresa_dual_button_3_button_2" "event.bilresa_dual_button_button_2_2" ];
    };
  };
  # Dashboard zones need not merge/rename the actual HA areas. Retain the old
  # individual-room arguments for existing callers, but don't show extra cards.
  roomAreas = {
    bedroom = [ "bedroom" ];
    living_kitchen = [ "living_room" "kitchen" ];
    bathroom = [ "bathroom" ];
    living_room = [ "living_room" ];
    kitchen = [ "kitchen" ];
  };
}
