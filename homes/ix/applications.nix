# Deliberate headless tools, not the desktop/personal Home Manager profile.
{ config, pkgs, ... }:
{
  imports = [
    ./mail.nix
    ./syncthing.nix
    ./editor-tools.nix
    ./hindsight.nix
    ../../modules/shared/config/emacs/emacs-service.nix
    ../../modules/shared/config/fish/fish.nix
  ];

  home.packages = with pkgs; [
    pi-coding-agent
    codex
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

  afm.emacsService = {
    enable = true;
    package = pkgs.emacs-nox;
    clientEnable = false;
    timeoutStartSec = "5min";
    startLimitIntervalSec = 60;
    startLimitBurst = 3;
    earlyInitFile = "${config.home.homeDirectory}/.local/share/src/nixos-config/homes/ix/emacs-early-init.el";
    initFile = "${config.home.homeDirectory}/.local/share/src/nixos-config/homes/ix/emacs.el";
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
  # Pin the skill in the Nix store; Pi discovers this directory automatically.
  home.file.".pi/agent/skills/emacs-pair".source = "${
    pkgs.fetchFromGitHub {
      owner = "afermg";
      repo = "emacs-pair";
      rev = "c06fbe7b1437f49b7d5d06e5fe4d87af0b9df281";
      hash = "sha256-kOBVPtRzDHzVm+Rk0Mn+FUFoCD++Us6ocYxrUmDgcVk=";
    }
  }/skills/emacs-pair";
  home.file.".pi/agent/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/share/src/nixos-config/homes/ix/pi-settings.json";
}
