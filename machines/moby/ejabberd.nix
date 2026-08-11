{ outputs, ... }:
{
  imports = [ outputs.nixosModules.ejabberd-tailscale ];

  services.ejabberd-tailscale = {
    enable = true;
    domain = "moby.tail5e510f.ts.net";
    tailscaleIPv4 = "100.94.5.85";
  };
}
