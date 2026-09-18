{ ... }:
{
  services.home-assistant = {
    enable = true;
    openFirewall = false;

    # Replace the module's broad defaults. Onboarding sets up Met.no weather;
    # add other integration names here as you start using them in the UI.
    extraComponents = [ "met" ];

    config = {
      # Deliberately omit default_config: no automatic network discovery,
      # Bluetooth, cloud integration, or history database to start with.
      frontend = { };

      # Moby's firewall is disabled, so bind explicitly to loopback.
      # Use an SSH tunnel for access from another computer.
      http = {
        server_host = "127.0.0.1";
        server_port = 8123;
      };
    };
  };
}
