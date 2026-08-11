{ pkgs, ... }:
let
  emacsPackage = pkgs.emacs.override {
    withImageMagick = true;
    withXwidgets = false; # https://github.com/nix-community/emacs-overlay/issues/466
  };
in
{
  # `services.emacs.package` controls the daemon executable but does not add
  # Emacs or emacsclient to the Home Manager profile. Enable the program too
  # so both commands remain available on PATH.
  programs.emacs = {
    enable = true;
    package = emacsPackage;
  };

  services.emacs = {
    enable = true;
    startWithUserSession = "graphical";
    package = emacsPackage.pkgs.withPackages (_epkgs: [ ]);
  };
}
