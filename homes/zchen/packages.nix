{ pkgs }:
with pkgs;
let
  shared-packages = import ../../modules/shared/packages.nix { inherit pkgs; };
in
[
  # To support pdbpp in emacs
  autoconf
  automake

  # faster/better X
  ripgrep # faster grep in rust
  fd # faster find
  difftastic # better diffs
  dua # better du
  dust # interactive du in rust
  bottom # network top

  # langs
  cmake # c compiler
  clang # c language
  clang-tools # tools for c language

  uv
  conda
]
# Packages shared across users and devices
++ shared-packages
# Linux-only packages
++ pkgs.lib.optionals pkgs.stdenv.isLinux [
]
