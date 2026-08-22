{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.marimohub-nix.nixosModules.marimohub
  ];

  age.secrets.cloudflared-marimohub = {
    file = ../../secrets/cloudflared-marimohub.age;
    owner = "cloudflared";
    group = "cloudflared";
    mode = "0400";
  };

  age.secrets.marimohub-google = {
    file = ../../secrets/marimohub-google.age;
    owner = "marimohub";
    group = "marimohub";
    mode = "0400";
  };

  services.marimohub = {
    enable = true;
    listenAddress = "127.0.0.1";
    # Keep MarimoHub on its established distinct origin.
    # The Cloudflare dashboard ingress must target http://localhost:18081
    # before this module is re-enabled in ./default.nix.
    port = 18081;

    podman = {
      enable = true;
      nvidia.enable = true;
    };

    google = {
      enable = true;
      clientId = "192946256037-g5fef3k37ecih26lgtl6jbjqvivujth8.apps.googleusercontent.com";
      redirectUri = "https://hub.quasimorphic.com/api/auth/callback";
      environmentFile = config.age.secrets.marimohub-google.path;
      allowedEmails = [
        "alan@quasimorphic.com"
      ];
    };

    settings = {
      MARIMOHUB_STORAGE_BACKEND = "fs";
      MARIMOHUB_STORAGE_FS_ROOT = "/var/lib/marimohub/storage";

      # The Cloudflare Tunnel terminates public HTTPS and forwards to the
      # dedicated loopback origin on port 18081. Authentication remains direct
      # Google OIDC in marimohub.
      MARIMOHUB_APP_BASE_URL = "https://hub.quasimorphic.com";
      MARIMOHUB_SANDBOX_EXPOSURE = "proxy";
      MARIMOHUB_SANDBOX_PROXY_ACK_UNTRUSTED = true;

      # Keep uninvited Google users from seeing existing projects; admins invite
      # collaborators by verified email from the project members dialog.
      MARIMOHUB_DEFAULT_ROLE = "none";
      MARIMOHUB_VIEWER_MODE = "static";

      MARIMOHUB_RUN_MAINTENANCE = true;
    };
  };

  virtualisation.podman.autoPrune.enable = true;

  users.users.cloudflared = {
    isSystemUser = true;
    group = "cloudflared";
    description = lib.mkDefault "Cloudflare Tunnel connector";
  };
  users.groups.cloudflared = { };

  systemd.services.cloudflared-marimohub = {
    description = "Cloudflare Tunnel — hub.quasimorphic.com";
    after = [
      "network-online.target"
      "marimohub.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "notify";
      User = "cloudflared";
      Group = "cloudflared";
      EnvironmentFile = config.age.secrets.cloudflared-marimohub.path;
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared --no-autoupdate tunnel --protocol http2 --edge-ip-version 4 run";
      Restart = "on-failure";
      RestartSec = "5s";

      # Connector only needs outbound HTTPS/WebSockets to Cloudflare and local
      # access to 127.0.0.1:18081.
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      # cloudflared reports readiness to systemd over an sd_notify socket.
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
      MemoryDenyWriteExecute = true;
      LockPersonality = true;
    };
  };
}
