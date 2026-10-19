{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.hindsightServer;
  runner = pkgs.writeShellApplication {
    name = "hindsight-server";
    runtimeInputs = with pkgs; [
      age
      coreutils
      curl
      podman
      python3
      tailscale
    ];
    text = builtins.readFile ./server.sh;
  };
in
{
  options.services.hindsightServer = {
    enable = lib.mkEnableOption "personal, rootless Hindsight server on Oppy";
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = runner;
      description = "Hindsight service and encrypted-backup runner.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "The Hindsight server requires Linux, rootless Podman, and user lingering.";
      }
    ];
    home.packages = [ runner ];
    systemd.user.services.hindsight-api = {
      Unit = {
        Description = "Shared Hindsight API (rootless, Oppy)";
        After = [
          "network-online.target"
          "agenix.service"
        ];
        Wants = [ "network-online.target" ];
        StartLimitIntervalSec = 600;
        StartLimitBurst = 3;
      };
      Service = {
        ExecStart = "${runner}/bin/hindsight-server start";
        ExecStartPost = "${runner}/bin/hindsight-server ready";
        ExecStop = "${runner}/bin/hindsight-server stop";
        Restart = "on-failure";
        RestartSec = 15;
        TimeoutStartSec = 600;
        TimeoutStopSec = 60;
        UMask = "0077";
      };
      Install.WantedBy = [ "default.target" ];
    };
    systemd.user.services.hindsight-backup = {
      Unit = {
        Description = "Encrypted Hindsight backup (Oppy)";
        Requires = [ "hindsight-api.service" ];
        After = [ "hindsight-api.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${runner}/bin/hindsight-server backup";
        TimeoutStartSec = 1800;
        UMask = "0077";
      };
    };
    systemd.user.timers.hindsight-backup = {
      Unit.Description = "Weekly encrypted Hindsight backup (Oppy)";
      Timer = {
        OnCalendar = "Sun *-*-* 03:15:00";
        RandomizedDelaySec = "30m";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
