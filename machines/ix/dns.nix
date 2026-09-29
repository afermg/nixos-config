{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  publicConfig =
    (pkgs.formats.yaml { }).generate "blocky-public.yaml"
      config.services.blocky.settings;
  # Reserve this lease on the Verizon router before advertising it as LAN DNS.
  lanAddress = "192.168.1.162";
  lanDnsRule =
    protocol:
    "-i end0 -s 192.168.1.0/24 -d ${lanAddress}/32 -p ${protocol} --dport 53 -m comment --comment ix-blocky-lan-${protocol} -j nixos-fw-accept";
in
{
  imports = [ inputs.agenix.nixosModules.default ];

  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  age.secrets.blocky-private = {
    file = ../../secrets/blocky-private.yaml.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

  services.blocky = {
    enable = true;
    enableConfigCheck = true;
    settings = {
      ports = {
        dns = [
          "100.114.49.10:53"
          "${lanAddress}:53"
        ];
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
        denylists.ads = [
          "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
          # HaGeZi Multi NORMAL; upstream recommends wildcard syntax for Blocky >= 0.23.
          "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/multi.txt"
        ];
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
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wants = [
      "network-online.target"
      "tailscaled.service"
    ];
    restartTriggers = [ config.age.secrets.blocky-private.file ];
    serviceConfig = {
      RestartSec = "20s";
      # systemd copies root-only secrets into this service's private credential
      # directory. Blocky merges YAML files in lexical order at runtime.
      LoadCredential = [
        "00-public.yaml:${publicConfig}"
        "10-private.yaml:${config.age.secrets.blocky-private.path}"
      ];
      ExecStartPre = [ "${lib.getExe config.services.blocky.package} --config %d validate" ];
      ExecStart = lib.mkForce "${lib.getExe config.services.blocky.package} --config %d";
    };
  };

  # LAN-only IPv4 DNS access; do not open port 53 globally or on public IPv6.
  # Keep the management API loopback-only and the existing Tailscale access.
  networking.firewall.extraCommands = ''
    iptables -w -A nixos-fw ${lanDnsRule "tcp"}
    iptables -w -A nixos-fw ${lanDnsRule "udp"}
  '';
  networking.firewall.extraStopCommands = ''
    iptables -w -D nixos-fw ${lanDnsRule "tcp"} 2>/dev/null || true
    iptables -w -D nixos-fw ${lanDnsRule "udp"} 2>/dev/null || true
  '';

  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [ 53 ];
    allowedUDPPorts = [ 53 ];
  };
}
