# Dedicated ZBT-2 Thread radio; commissioning uses Bluetooth on the Android phone.
# Thread datasets and Matter fabric keys are runtime state, never Nix values.
{ config, lib, pkgs, ... }:
let
  # Follow the configured Matter controller's SDK, not Home Assistant's version
  # or the host's default Python package set. Fail visibly if upstream changes
  # packaging rather than silently using an unrelated OTA binary.
  chipCore = lib.findFirst
    (dependency: (dependency.pname or "") == "home-assistant-chip-core")
    null
    (config.services.matter-server.package.dependencies or [ ]);
  otaProvider =
    if chipCore == null then
      throw "ix Matter OTA: configured Matter Server has no CHIP core dependency"
    else
      pkgs.callPackage ./packages/matter-ota-provider.nix {
        chipWheels = chipCore.src;
      };
in
{
  # One ZBT-2 on ix. Stable across ttyACM renumbering, without publishing its serial.
  services.udev.extraRules = ''
    SUBSYSTEM=="tty", ATTRS{idVendor}=="303a", ATTRS{idProduct}=="831a", SYMLINK+="home-assistant-thread", TAG+="systemd", ENV{SYSTEMD_WANTS}+="otbr-agent.service"
  '';

  services.openthread-border-router = {
    enable = true;
    backboneInterfaces = [ "end0" ];
    interfaceName = "wpan0";
    radio = {
      device = "/dev/home-assistant-thread";
      baudRate = 460800;
      flowControl = true;
      # uart-reset prevents this ZBT-2 firmware from completing the Spinel handshake.
      urlQueryString = "uart-exclusive";
    };
    rest.listenAddress = "127.0.0.1";
    openFirewall = false;
    web.enable = false;
  };
  systemd.services.otbr-agent = {
    # Missing hardware must not delay host boot; udev starts us on attachment.
    unitConfig.ConditionPathExists = "/dev/home-assistant-thread";
    serviceConfig.StateDirectoryMode = "0700";
  };

  services.matter-server = {
    enable = true;
    # DCL currently contains an ASN.1-invalid PAA certificate. Reject that one
    # certificate, not the entire server startup; retain all trust validation.
    package = pkgs.python-matter-server.overridePythonAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/matter-skip-malformed-paa.patch ];
      postPatch = (old.postPatch or "") + ''
        cp ${./tests/test_matter_paa.py} tests/test_ix_paa.py
      '';
    });
    openFirewall = false;
    extraArgs = {
      listen-address = "127.0.0.1";
      primary-interface = "end0";
    };
  };
  # The upstream NixOS service otherwise cannot find chip-ota-provider-app.
  # Nix regenerates PATH and retains the matching helper on each deployment.
  systemd.services.matter-server.path = [ otaProvider ];
  systemd.services.matter-server.serviceConfig = {
    Restart = "on-failure";
    RestartSec = "5s";
    StateDirectoryMode = "0700";
  };

  services.home-assistant = {
    extraComponents = [
      "matter"
      "otbr"
      "thread"
    ];
    config.zeroconf = { };
  };

  # mDNS is link-local and restricted to the home Ethernet interface.
  # No management API ports (5580/8081/8082) are opened, including on Tailscale.
  networking.firewall.interfaces.end0.allowedUDPPorts = [ 5353 ];
  networking.firewall.extraCommands = lib.mkAfter ''
    # Sleepy Thread devices can report after UDP conntrack expires. The CHIP
    # controller uses an ephemeral local port, so match their Matter source port.
    ip6tables -w -A nixos-fw -i wpan0 -s fc00::/7 -p udp --sport 5540 -m comment --comment ix-thread-matter -j nixos-fw-accept
  '';
  networking.firewall.extraStopCommands = lib.mkAfter ''
    ip6tables -w -D nixos-fw -i wpan0 -s fc00::/7 -p udp --sport 5540 -m comment --comment ix-thread-matter -j nixos-fw-accept 2>/dev/null || true
  '';
}
