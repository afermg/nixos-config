{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nix.armEmulation;
  hostSystem = pkgs.stdenv.hostPlatform.system;
in
{
  options.nix.armEmulation = {
    enable = lib.mkEnableOption "emulated ARM Linux builds with Nix";

    systems = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        lib.optionals (hostSystem != "aarch64-linux") [
          "aarch64-linux"
        ]
        ++ [
          "armv7l-linux"
        ];
      description = ''
        Linux system types that Nix may build locally through binfmt emulation.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.binfmt.emulatedSystems = cfg.systems;
  };
}
