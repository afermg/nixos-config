{ ... }:
{
  services.home-assistant = {
    enable = true;

    # Replace the module's broad defaults. Onboarding sets up Met.no weather;
    # add other integration names here as you start using them in the UI.
    extraComponents = [ "met" ];

    config = {
      # Deliberately omit default_config: no automatic network discovery,
      # Bluetooth, Home Assistant Cloud, or history database to start with.
      frontend = { };

      # Keep this for the one-time HTTP settings migration in HA 2026.9.
      # Moby's firewall is disabled, so preserve the loopback-only listener.
      # After migration, HTTP settings are managed in the UI; see docs/home-assistant.md.
      http = {
        server_host = "127.0.0.1";
        server_port = 8123;
      };
    };
  };
}
