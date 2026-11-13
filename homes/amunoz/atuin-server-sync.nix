# Explicit opt-in for the personal Oppy, Spirit and Karkinos server profiles.
# Keep capture off in the generic profile and on personal laptops/Moby.
{ ... }:
{
  programs.atuinThreads = {
    enable = true;
    capture = true;
    captureTools = false;
  };
  programs.atuin.settings.daemon.sync_frequency = 300;
}
