{ lib, pkgs, ... }:
let
  emacsPackage = pkgs.emacs.override {
    withImageMagick = true;
    withXwidgets = false; # https://github.com/nix-community/emacs-overlay/issues/466
  };
in
{
  programs.emacs = {
    enable = true;
    package = emacsPackage;
  };

  services.emacs = {
    enable = true;
    startWithUserSession = true;
  };

  systemd.user.services.emacs = lib.mkIf pkgs.stdenv.isLinux {
    Service = {
      Restart = lib.mkForce "always";
      RestartSec = "5s";
    };
  };
}
