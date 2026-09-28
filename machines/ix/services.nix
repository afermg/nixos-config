# Independent, fresh services; no Home Assistant state is imported from moby.
{ ... }:
{
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22000 ];

  services.home-assistant = {
    enable = true;
    extraComponents = [ "met" ]; # Weather integration offered during onboarding.
    config = {
      frontend = { };
      # No default_config, discovery, Bluetooth, recorder, or device integrations.
      # HA 2026.9 migrates these initial values into its own HTTP settings.
      http = {
        server_host = "127.0.0.1";
        server_port = 8123;
      };
    };
  };
}
