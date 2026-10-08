# Personal shell history uses Atuin's encrypted sync protocol, not file sync.
{
  config,
  lib,
  pkgs,
  amunozInputs,
  ...
}:
let
  # Exported profiles must use this flake's pin, not a consumer's older package.
  atuin = amunozInputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.atuin;
  home = config.home.homeDirectory;
  keyPath = "${home}/.local/share/atuin/key";
  darwinDaemon = pkgs.writeShellScript "atuin-daemon-with-key" ''
    # launchd has no After/Requires equivalent. Wait for the agenix LaunchAgent
    # instead of letting Atuin generate a different encryption key at login.
    for attempt in {1..60}; do
      if test -r ${lib.escapeShellArg keyPath} && test -s ${lib.escapeShellArg keyPath}; then
        exec ${lib.getExe atuin} daemon start
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
    echo "Atuin: shared encryption key is unavailable; check agenix" >&2
    exit 1
  '';
in
{
  age.secrets.atuin = {
    file = ../../../../secrets/atuin.age;
    path = keyPath;
    mode = "0400";
  };

  programs.atuin = {
    enable = true;
    package = atuin;
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
    daemon.enable = true;
    flags = [ "--disable-up-arrow" ];
    settings = {
      key_path = keyPath;
      auto_sync = true;
      sync_frequency = "5m";
      daemon.sync_frequency = 300;
      sync_address = "https://api.atuin.sh";
      filter_mode = "global";
      search_mode = "prefix";
      secrets_filter = true;
      update_check = false; # Nix manages the installed version.
    };
  };

  # Keep the existing login helper available on lightweight profiles as well.
  # Credentials are fetched only at runtime, never evaluated into the Nix store.
  home.packages = [
    (pkgs.writeShellApplication {
      name = "atuin-relogin";
      runtimeInputs = [
        atuin
        pkgs.rbw
      ];
      text = ''
        test -s ${lib.escapeShellArg keyPath} || {
          echo "Atuin: activate the shared agenix key before logging in" >&2
          exit 1
        }
        exec ${pkgs.python3.withPackages (ps: [ ps.pexpect ])}/bin/python ${./login.py}
      '';
    })
  ];

  home.activation.atuinPrivateState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -d -m 0700 "${home}/.local/share/atuin"
  '';

  systemd.user.services.atuin-daemon = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    Unit = {
      After = [ "agenix.service" ];
      Requires = [ "agenix.service" ];
    };
    Service = {
      ExecStartPre = [ "${pkgs.coreutils}/bin/test -s ${lib.escapeShellArg keyPath}" ];
      UMask = "0077";
    };
  };

  launchd.agents.atuin-daemon.config = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    ProgramArguments = lib.mkForce [ (toString darwinDaemon) ];
    Umask = 63; # 0077 in decimal.
    ThrottleInterval = 30;
  };
}
