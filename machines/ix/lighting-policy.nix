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
      manual = "input_boolean.lighting_manual_living_kitchen";
      automation = "automation.myggspray_living_room_and_kitchen_when_dark";
      active = "input_boolean.myggspray_lighting_active";
      lights = [
        "light.kajplats_e26_ws_globe_1600lm"
        "light.living_room_kajplats_e26_living_room_1100lm"
        "light.kitchen_kajplats_e26_kitchen_1100lm"
      ];
    };
    bathroom = {
      name = "Bathroom";
      manual = "input_boolean.lighting_manual_bathroom";
      automation = "automation.myggspray_bathroom_night_light";
      active = "input_boolean.myggspray_bathroom_lighting_active";
      lights = [ "light.bathroom_kajplats_e26_1100lm_bathroom_2" ];
    };
  };
  rooms = [ "bedroom" "living_kitchen" "bathroom" ];
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
