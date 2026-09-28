# Deliberate headless tools, not the desktop/personal Home Manager profile.
{ config, pkgs, ... }:
{
  imports = [
    ./mail.nix
    ./syncthing.nix
    ./editor-tools.nix
    ../../modules/shared/config/fish/fish.nix
  ];

  home.packages = with pkgs; [
    pi-coding-agent
    ripgrep
    fd
    jq
    oama
  ];
  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];
  home.sessionVariables = {
    EDITOR = "emacsclient -t -a emacs";
    VISUAL = "emacsclient -t -a emacs";
    PI_SKIP_VERSION_CHECK = "1"; # Nix manages the installed Pi version.
    PI_TELEMETRY = "0";
  };
  programs.git.lfs.enable = true;
  programs.gpg.enable = true;
  programs.npm = {
    enable = true;
    settings.prefix = "${config.home.homeDirectory}/.local";
  };

  programs.emacs = {
    enable = true;
    package = pkgs.emacs-nox;
    # Keep mu4e native/matched. Shared Lisp packages remain managed by Straight.
    extraPackages = epkgs: [
      epkgs.mu4e
      epkgs.exec-path-from-shell
      (epkgs.treesit-grammars.with-grammars (
        grammars: with grammars; [
          tree-sitter-bash
          tree-sitter-c
          tree-sitter-cpp
          tree-sitter-css
          tree-sitter-html
          tree-sitter-javascript
          tree-sitter-json
          tree-sitter-nix
          tree-sitter-python
          tree-sitter-rust
          tree-sitter-toml
          tree-sitter-typescript
          tree-sitter-yaml
        ]
      ))
    ];
  };
  services.emacs = {
    enable = true;
    startWithUserSession = true;
    client.enable = false;
  };
  systemd.user.services.emacs = {
    Unit = {
      StartLimitIntervalSec = 60;
      StartLimitBurst = 3;
    };
    Service.RestartSec = 5;
  };
  home.file.".emacs.d/init.el".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/share/src/nixos-config/homes/ix/emacs.el";
  home.file.".pi/agent/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/share/src/nixos-config/homes/ix/pi-settings.json";
}
