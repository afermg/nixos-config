{ ... }:
{
  services.blocky = {
    enable = true;
    enableConfigCheck = true;
    settings = {
      ports = {
        dns = "100.114.49.10:53";
        http = "127.0.0.1:4000";
      };
      upstreams.groups.default = [
        "https://dns.quad9.net/dns-query"
        "https://cloudflare-dns.com/dns-query"
      ];
      bootstrapDns = [
        {
          upstream = "https://dns.quad9.net/dns-query";
          ips = [
            "9.9.9.9"
            "149.112.112.112"
          ];
        }
      ];
      blocking = {
        denylists.ads = [ "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" ];
        allowlists.ads = [
          ''
            tailscale.com
            tail5e510f.ts.net
          ''
        ];
        clientGroupsBlock.default = [ "ads" ];
      };
      caching = {
        minTime = "5m";
        maxTime = "24h";
      };
      prometheus.enable = false;
      queryLog = {
        type = "console";
        logRetentionDays = 7;
      };
    };
  };

  systemd.services.blocky = {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    serviceConfig.RestartSec = "20s";
  };

  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [ 53 ];
    allowedUDPPorts = [ 53 ];
  };
}
