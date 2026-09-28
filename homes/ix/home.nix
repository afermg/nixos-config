# Intentionally independent from homeModules.amunoz and the desktop profile.
# Applications were added only after normal boot, recovery, and rollback passed.
{ ... }:
{
  imports = [ ./applications.nix ];
  home = {
    username = "amunoz";
    homeDirectory = "/home/amunoz";
    stateVersion = "26.05";
  };
  programs.home-manager.enable = true;
  programs.bash.enable = true;
  programs.git = {
    enable = true;
    settings.user = {
      name = "Alán F. Muñoz";
      email = "afer.mg@gmail.com";
    };
  };
  xdg.enable = true;
}
