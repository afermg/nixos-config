{ pkgs }:
with pkgs;
let
  shared-packages = import ../../modules/shared/packages.nix { inherit pkgs; };
in
[
  awscli
  screen
  git
  tldr
  killall
]
# Packages shared across users and devices
++ shared-packages
# Linux-only packages
++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
]
