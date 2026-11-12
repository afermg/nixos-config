# Run from the repo root:
# nix eval --impure --json --expr 'import ./tests/atuin-threads.nix { flake = builtins.getFlake (toString ./.); }'
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  mkConfig =
    system: extra:
    (flake.inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = flake.inputs.nixpkgs.legacyPackages.${system};
      modules = [
        flake.homeModules.atuin-threads
        {
          home = {
            username = "test";
            homeDirectory = if lib.hasSuffix "darwin" system then "/Users/test" else "/home/test";
            stateVersion = "24.05";
          };
          programs.atuin.enable = true;
        }
        extra
      ];
    }).config;
  disabled = mkConfig "x86_64-linux" { };
  ready = mkConfig "x86_64-linux" { programs.atuinThreads.enable = true; };
  capture = mkConfig "x86_64-linux" {
    programs.atuinThreads = {
      enable = true;
      capture = true;
    };
    programs.atuin.settings.key_path = "/home/test/custom-key";
  };
  tools = mkConfig "x86_64-linux" {
    programs.atuinThreads = {
      enable = true;
      capture = true;
      captureTools = true;
    };
  };
  darwin = mkConfig "aarch64-darwin" {
    programs.atuinThreads = {
      enable = true;
      capture = true;
    };
  };
  forcedOld = mkConfig "x86_64-linux" {
    programs.atuinThreads.enable = true;
    programs.atuin.package = lib.mkForce (
      flake.inputs.nixpkgs.legacyPackages.x86_64-linux.atuin // { version = "18.21.0"; }
    );
  };
  noAtuin = mkConfig "x86_64-linux" {
    programs.atuinThreads.enable = true;
    programs.atuin.enable = lib.mkForce false;
  };
  failed = cfg: map (a: a.message) (builtins.filter (a: !a.assertion) cfg.assertions);
  hasLauncher = cfg: builtins.any (p: lib.getName p == "atuin-mcp") cfg.home.packages;
  checks = {
    disabledIsInert = !(disabled.programs.atuin.settings ? threads) && !(hasLauncher disabled);
    captureIsOptIn =
      ready.programs.atuin.settings.threads == {
        capture = false;
        capture_tools = false;
      };
    readyDoesNotStartDaemon = !ready.programs.atuin.daemon.enable;
    versionSupported = lib.versionAtLeast (lib.getVersion ready.programs.atuin.package) "18.24";
    launcherInstalled = hasLauncher ready;
    captureStartsDaemon = capture.programs.atuin.daemon.enable;
    toolsAreOptIn =
      !capture.programs.atuin.settings.threads.capture_tools
      && tools.programs.atuin.settings.threads.capture_tools;
    linuxKeyGuard = builtins.any (
      cmd: lib.hasSuffix "-s /home/test/custom-key" cmd
    ) capture.systemd.user.services.atuin-daemon.Service.ExecStartPre;
    linuxPrivateState = capture.systemd.user.services.atuin-daemon.Service.UMask == "0077";
    darwinDaemon =
      darwin.programs.atuin.daemon.enable && darwin.launchd.agents.atuin-daemon.config.Umask == 63;
    darwinKeyGuard = lib.hasSuffix "atuin-threads-daemon-with-key" (
      builtins.head darwin.launchd.agents.atuin-daemon.config.ProgramArguments
    );
    validConfigurations = builtins.all (c: failed c == [ ]) [
      disabled
      ready
      capture
      tools
      darwin
    ];
    rejectsForcedOldPackage = !(builtins.tryEval forcedOld).success;
    requiresAtuin = !(builtins.tryEval noAtuin).success;
  };
in
assert lib.assertMsg (builtins.all (x: x) (builtins.attrValues checks)) (builtins.toJSON checks);
checks
