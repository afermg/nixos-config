{ ... }:
{
  imports = [ ../../modules/nixos/ejabberd-tailscale.nix ];

  services.ejabberd-tailscale = {
    enable = true;
    domain = "ix.tail5e510f.ts.net";
    tailscaleIPv4 = "100.114.49.10";
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
    5222
    5443
  ];
}
