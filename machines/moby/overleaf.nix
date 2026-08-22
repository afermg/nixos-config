# ARCHIVED CONFIGURATION — intentionally not imported by ./default.nix.
# See ./OVERLEAF_ARCHIVE.md for the active Oppy/Karkinos deployment and the
# safe procedure for restoring service on Moby in the future.
{
  config,
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    inputs.overleaf-nix.nixosModules.overleaf
  ];

  # Decrypted token containing TUNNEL_TOKEN=<...> for the cloudflared
  # tunnel that publishes overleaf.quasimorphic.com.
  age.secrets.cloudflared-overleaf = {
    file = ../../secrets/cloudflared-overleaf.age;
    owner = "cloudflared";
    group = "cloudflared";
    mode = "0400";
  };

  # Decrypted ~/.netrc containing the overleaf git-bridge personal access
  # token. Materialized at /home/amunoz/.netrc so git/libcurl's default
  # auth path picks it up; home-manager's git config then scopes the
  # `netrc` credential helper to overleaf.quasimorphic.com only.
  age.secrets.netrc-overleaf = {
    file = ../../secrets/netrc-overleaf.age;
    path = "/home/amunoz/.netrc";
    owner = "amunoz";
    group = "users";
    mode = "0600";
    symlink = false;
  };

  # Use MongoDB's prebuilt 8.0 release: the existing database still has FCV
  # 7.0, which 8.0 can upgrade, while nixpkgs' current 8.2 cannot start it.
  # Keep this explicit until the FCV has been upgraded and the 8.2 hop tested.
  services.mongodb.package = pkgs.mongodb-ce.overrideAttrs (_: {
    version = "8.0.28";
    src = pkgs.fetchurl {
      url = "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2404-8.0.28.tgz";
      hash = "sha256-MCC+2HO/6oaNc4jDpK/1lIxHaijNrD6JSu8wnv5RAPI=";
    };
  });

  services.overleaf = {
    enable = true;
    # Loopback only — Cloudflare Tunnel reaches us via outbound conn.
    host = "127.0.0.1";
    port = 18080;
    # Public URL users will type in the browser. Must match what
    # Cloudflare proxies, otherwise cookies/WebSocket origin checks break.
    siteUrl = "https://overleaf.quasimorphic.com";
    appName = "Quasimorphic Overleaf";

    # git-bridge — clone projects via `git clone https://overleaf.../git/<id>`.
    # Listens on 127.0.0.1:8000; the public-facing nginx vhost adds a
    # `/git/` proxy automatically when this is enabled.
    gitBridge = {
      enable = true;
      package = pkgs.callPackage ./overleaf-git-bridge.nix { };
      apiBaseUrl = "http://127.0.0.1:18080/api/v0";
    };
  };

  # Cloudflare Tunnel exposes 127.0.0.1:18080 to the public internet
  # under https://overleaf.quasimorphic.com via Cloudflare's edge.
  # The tunnel + ingress mappings are managed in the Cloudflare dashboard;
  # this side just runs the connector with the token.
  users.users.cloudflared = {
    isSystemUser = true;
    group = "cloudflared";
    description = "Cloudflare Tunnel connector";
  };
  users.groups.cloudflared = { };

  systemd.services.cloudflared-overleaf = {
    description = "Cloudflare Tunnel — overleaf.quasimorphic.com";
    after = [
      "network-online.target"
      "overleaf-web.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "notify";
      User = "cloudflared";
      Group = "cloudflared";
      EnvironmentFile = config.age.secrets.cloudflared-overleaf.path;
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared --no-autoupdate tunnel --protocol http2 --edge-ip-version 4 run";
      Restart = "on-failure";
      RestartSec = "5s";
      # Hardening — connector only needs outbound TCP/443 to Cloudflare.
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
