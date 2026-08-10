{
  config,
  pkgs,
  ...
}:

let
  privateOriginAddress = "100.79.40.39";
  cloudflaredEnv = config.age.secrets.cloudflared-marimohub-quasimorphic.path;
  cloudflaredConfig = pkgs.writeText "cloudflared-marimohub-quasimorphic.yml" ''
    ingress:
      - hostname: marimohub.quasimorphic.com
        path: ^/dex(/.*)?$
        service: http://127.0.0.1:5556
      - hostname: marimohub.quasimorphic.com
        service: http://127.0.0.1:18081
      - service: http_status:404
  '';
  checkCloudflaredEnv = pkgs.writeShellScript "check-cloudflared-marimohub-quasimorphic-env" ''
    set -eu

    value="''${TUNNEL_TOKEN-}"
    if [ -z "$value" ]; then
      echo "cloudflared marimohub env is missing TUNNEL_TOKEN" >&2
      exit 1
    fi
    case "$value" in
      *replace-me*)
        echo "cloudflared marimohub env still contains a placeholder TUNNEL_TOKEN" >&2
        exit 1
        ;;
    esac
  '';
in
{
  age.secrets.cloudflared-marimohub-quasimorphic = {
    file = ../../secrets/cloudflared-marimohub-quasimorphic.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  users.groups.cloudflared = { };
  users.users.cloudflared = {
    isSystemUser = true;
    group = "cloudflared";
    description = "Cloudflare Tunnel connector";
  };

  # Preserve the Cloudflare dashboard's localhost origins while carrying the
  # origin traffic over the private network.
  systemd.sockets.marimohub-private-origin = {
    description = "Local marimohub origin socket";
    wantedBy = [ "sockets.target" ];
    listenStreams = [ "127.0.0.1:18081" ];
  };

  systemd.services.marimohub-private-origin = {
    description = "Private marimohub origin";
    serviceConfig = {
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd ${privateOriginAddress}:18081";
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
    };
  };

  systemd.sockets.dex-private-origin = {
    description = "Local marimohub Dex origin socket";
    wantedBy = [ "sockets.target" ];
    listenStreams = [ "127.0.0.1:5556" ];
  };

  systemd.services.dex-private-origin = {
    description = "Private Dex origin";
    serviceConfig = {
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd ${privateOriginAddress}:5556";
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
    };
  };

  systemd.services.cloudflared-marimohub-quasimorphic = {
    description = "Cloudflare Tunnel — marimohub.quasimorphic.com";
    after = [
      "network-online.target"
      "marimohub-private-origin.socket"
      "dex-private-origin.socket"
    ];
    wants = [
      "network-online.target"
      "marimohub-private-origin.socket"
      "dex-private-origin.socket"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "notify";
      User = "cloudflared";
      Group = "cloudflared";
      EnvironmentFile = cloudflaredEnv;
      ExecStartPre = checkCloudflaredEnv;
      # QUIC/UDP 7844 is blocked on Moby, while HTTP/2/TCP 7844 passes the
      # cloudflared connectivity precheck.
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared --no-autoupdate --config ${cloudflaredConfig} tunnel --protocol http2 --edge-ip-version 4 run";
      Restart = "on-failure";
      RestartSec = "5s";
      UMask = "0077";

      CapabilityBoundingSet = "";
      LockPersonality = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
    };
  };
}
