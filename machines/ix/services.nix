# Independent, fresh services; no Home Assistant state is imported from moby.
{ pkgs, ... }:
let
  # IPv4 only, on the home Ethernet network; never a global port opening.
  homeAssistantLanRule = "-i end0 -s 192.168.1.0/24 -d 192.168.1.0/24 -p tcp --dport 8124 -m comment --comment ix-home-assistant-lan -j nixos-fw-accept";
in
{
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22000 ];
  networking.firewall.extraCommands = ''
    iptables -w -A nixos-fw ${homeAssistantLanRule}
  '';
  networking.firewall.extraStopCommands = ''
    iptables -w -D nixos-fw ${homeAssistantLanRule} 2>/dev/null || true
  '';

  # Separate LAN endpoint preserves HA's loopback listener and SSH tunnels.
  # Bind to the device rather than a DHCP lease; IPv6/tailscale0 are excluded.
  systemd.sockets.home-assistant-lan = {
    description = "Home Assistant IPv4 home-LAN endpoint";
    wantedBy = [ "sockets.target" ];
    listenStreams = [ "0.0.0.0:8124" ];
    socketConfig.BindToDevice = "end0";
  };
  systemd.services.home-assistant-lan = {
    description = "Home Assistant LAN-to-loopback TCP proxy";
    requires = [ "home-assistant.service" ];
    after = [ "home-assistant.service" ];
    serviceConfig = {
      # Raw TCP preserves HTTP/WebSockets without trusting forwarded headers.
      # HA authentication is unchanged, but all proxy clients appear local:
      # never add a loopback trusted_networks authentication bypass to HA.
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:8123";
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_UNIX"
      ];
    };
  };

  services.home-assistant = {
    enable = true;
    # UI-configured integrations still need their Python dependencies in Nix.
    extraComponents = [
      "met" # Weather integration offered during onboarding.
      "roborock" # Configure the Roborock account in the Home Assistant UI.
    ];
    config = {
      frontend = { };
      # Companion-app registration needs this; its dependencies are inferred by Nix.
      mobile_app = { };
      # No default_config, automatic discovery, Bluetooth, or recorder.
      # HA 2026.9 migrates these initial values into its own HTTP settings.
      http = {
        server_host = "127.0.0.1";
        server_port = 8123;
      };
    };
  };
}
