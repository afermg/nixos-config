# User-started whole-home vacuum, then a separate mop pass. No startup commands.
{ pkgs, ... }:
let
  dashboard = {
    title = "Cleaning";
    views = [{
      title = "Roborock"; path = "roborock";
      cards = [
        { type = "markdown"; content = "## Vacuum first, then mop\nRuns a whole-flat vacuum-only pass, then a separate mop-only pass. Mopping waits for a new **successful whole-home completion record**, not merely docking. Uses balanced suction and the robot's standard mopping defaults. Previous fan/water/route preferences are restored after both passes succeed. Maps, room customisations, no-go areas and schedules are unchanged.\n\nStart from the dock, with no unfinished job, at least 50% charge and mop/water ready. Pause, errors, disconnection or external cleaning-mode changes cancel the follow-up. HA restart does not resume the sequence; the robot may finish its current pass independently."; }
        { type = "button"; name = "Vacuum, then mop"; icon = "mdi:robot-vacuum";
          tap_action = { action = "perform-action"; perform_action = "ix_roborock_sequence.start";
            confirmation.text = "Start a whole-flat vacuum pass followed by a separate mop pass?"; }; }
        { type = "button"; name = "Cancel sequence & dock"; icon = "mdi:stop-circle-outline";
          tap_action = { action = "perform-action"; perform_action = "ix_roborock_sequence.cancel"; }; }
        { type = "entities"; show_header_toggle = false; entities = [
          "sensor.ix_roborock_sequence"
          { type = "attribute"; entity = "sensor.ix_roborock_sequence"; attribute = "message"; name = "Sequence status"; }
          "vacuum.roborock_qx_revo_plus"
          "sensor.roborock_qx_revo_plus_battery"
          "sensor.roborock_qx_revo_plus_cleaning_progress"
          "select.roborock_qx_revo_plus_cleaning_mode"
        ]; }
      ];
    }];
  };
in {
  services.home-assistant = {
    customComponents = [(pkgs.buildHomeAssistantComponent {
      owner = "afermg"; domain = "ix_roborock_sequence"; version = "1.0.0";
      src = ./ha-components;
    })];
    config = {
      ix_roborock_sequence = {};
      lovelace.dashboards.flat-cleaning = {
        mode = "yaml"; title = "Cleaning"; icon = "mdi:robot-vacuum"; show_in_sidebar = true;
        filename = pkgs.writeText "flat-cleaning-dashboard.yaml" (builtins.toJSON dashboard);
      };
    };
  };
}
