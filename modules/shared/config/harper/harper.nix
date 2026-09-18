{ config, pkgs, ... }:
let
  # Harper follows the platform-native config directory by default.
  dictionaryPath =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "Library/Application Support/harper-ls/dictionary.txt"
    else
      ".config/harper-ls/dictionary.txt";
in
{
  # Keep Harper's interactive "add to dictionary" action writable while using
  # the Git-tracked repository file as the source shared by every computer.
  home.file.${dictionaryPath}.source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/share/src/nixos-config/modules/shared/config/harper/dictionary.txt";
}
