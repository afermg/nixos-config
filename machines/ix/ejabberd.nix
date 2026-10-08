{ pkgs, ... }:
{
  imports = [ ../../modules/nixos/ejabberd-tailscale.nix ];

  services.ejabberd-tailscale = {
    enable = true;
    domain = "ix.tail5e510f.ts.net";
    tailscaleIPv4 = "100.114.49.10";
  };

  # A crashed process previously remained failed indefinitely (Restart=no).
  # Retry transient failures, but stop after three starts in ten minutes rather
  # than repeatedly hammering a damaged Mnesia database or generating dumps.
  systemd.services.ejabberd = {
    startLimitIntervalSec = 600;
    startLimitBurst = 3;
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "30s";
    };
  };

  # Read-only protocol/certificate checks: detect a live-but-broken service too.
  # Failures remain visible in systemctl --failed and the journal. This does not
  # replace an independent off-host outage alert or fix failing storage.
  systemd.services.ix-xmpp-health = {
    description = "Check ix XMPP STARTTLS, authentication advertisement and HTTPS";
    after = [ "ejabberd.service" "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 ${./xmpp-health.py} --host ix.tail5e510f.ts.net --address 100.114.49.10";
      TimeoutStartSec = "40s";
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    };
  };
  systemd.timers.ix-xmpp-health = {
    description = "Check ix XMPP health every five minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
      RandomizedDelaySec = "15s";
      Unit = "ix-xmpp-health.service";
    };
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
    5222
    5443
  ];
}
