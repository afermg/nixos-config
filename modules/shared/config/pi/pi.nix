{ config, ... }:
{
  # Keep the tracked Pi settings file as the single source of truth while
  # exposing it at ~/.pi/agent/settings.json for live edits.
  home.file.".pi/agent/settings.json".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/.local/share/src/nixos-config/modules/shared/config/pi/settings.json";

  home.file.".pi/agent/model-allowlist.ts".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/.local/share/src/nixos-config/modules/shared/config/pi/model-allowlist.ts";

  home.file.".pi/agent/reliable-compaction.ts".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/.local/share/src/nixos-config/modules/shared/config/pi/reliable-compaction.ts";
}
