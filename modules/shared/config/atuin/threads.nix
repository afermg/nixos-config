# Agent history is a separate opt-in from shell history. Importing this module
# alone neither changes the Atuin package nor starts capturing conversations.
{
  config,
  lib,
  pkgs,
  atuinThreadsInputs,
  ...
}:
let
  cfg = config.programs.atuinThreads;
  keyPath = config.programs.atuin.settings.key_path or "${config.xdg.dataHome}/atuin/key";
  guardedDaemon = pkgs.writeShellScript "atuin-threads-daemon-with-key" ''
    # launchd cannot order against agenix. Never generate a replacement sync key.
    for attempt in {1..60}; do
      if test -r ${lib.escapeShellArg keyPath} && test -s ${lib.escapeShellArg keyPath}; then
        exec ${lib.getExe config.programs.atuin.package} daemon start
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
    echo "Atuin: encryption key unavailable; activate agenix or log in first" >&2
    exit 1
  '';
in
{
  options.programs.atuinThreads = {
    enable = lib.mkEnableOption "Atuin Threads and its MCP launcher";
    package = lib.mkOption {
      type = lib.types.package;
      default = atuinThreadsInputs.nixpkgs-atuin.legacyPackages.${pkgs.stdenv.hostPlatform.system}.atuin;
      description = "Threads-capable Atuin package, independent of the system nixpkgs pin.";
    };
    capture = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Capture supported local agent conversations into Atuin's record store.
        Existing Atuin sync also syncs these records, end-to-end encrypted.
        This is not restricted to sessions launched by T3.
      '';
    };
    captureTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Also retain tool arguments and results; these may contain sensitive file contents.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.versionAtLeast (lib.getVersion config.programs.atuin.package) "18.24";
        message = "Atuin Threads requires Atuin >= 18.24.";
      }
      {
        assertion = config.programs.atuin.enable;
        message = "Enable programs.atuin before enabling programs.atuinThreads.";
      }
    ];

    programs.atuin = {
      package = cfg.package;
      daemon.enable = lib.mkIf cfg.capture true;
      settings.threads = {
        capture = cfg.capture;
        capture_tools = cfg.captureTools;
      };
    };

    systemd.user.services.atuin-daemon.Service =
      lib.mkIf (cfg.capture && pkgs.stdenv.hostPlatform.isLinux)
        {
          ExecStartPre = [ "${pkgs.coreutils}/bin/test -s ${lib.escapeShellArg keyPath}" ];
          UMask = "0077";
        };
    launchd.agents.atuin-daemon.config = lib.mkIf (cfg.capture && pkgs.stdenv.hostPlatform.isDarwin) {
      ProgramArguments = lib.mkForce [ (toString guardedDaemon) ];
      Umask = 63; # 0077 in decimal.
      ThrottleInterval = 30;
    };

    # An absolute executable can be registered with a provider even when T3's
    # service PATH predates a Home Manager activation. Do not mutate providers'
    # writable config/auth files or run imports/login during activation.
    home.packages = [
      (pkgs.writeShellScriptBin "atuin-mcp" ''
        exec ${lib.getExe config.programs.atuin.package} mcp "$@"
      '')
    ];
  };
}
