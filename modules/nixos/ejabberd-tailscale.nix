{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ejabberd-tailscale;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  epmdPort = toString cfg.epmdPort;
  tlsDir = "/var/lib/ejabberd/tls";
  certFile = "${tlsDir}/${cfg.domain}.crt";
  keyFile = "${tlsDir}/${cfg.domain}.key";

  ejabberdConfig = pkgs.writeText "ejabberd-tailscale.yml" ''
    hosts:
      - "${cfg.domain}"

    loglevel: info

    # Certificates are supplied by Tailscale, not ejabberd's ACME client.
    acme:
      auto: false

    certfiles:
      - "${certFile}"
      - "${keyFile}"

    # Store only SCRAM-SHA-256 verifiers, never plaintext passwords.
    auth_method: internal
    auth_password_format: scram
    auth_scram_hash: sha256

    listen:
      -
        port: 5222
        ip: "${cfg.tailscaleIPv4}"
        module: ejabberd_c2s
        max_stanza_size: 262144
        shaper: c2s_shaper
        access: c2s
        starttls_required: true
      -
        port: 5443
        ip: "${cfg.tailscaleIPv4}"
        module: ejabberd_http
        tls: true
        request_handlers:
          /upload: mod_http_upload

    acl:
      local:
        user_regexp: ""
      loopback:
        ip:
          - 127.0.0.0/8
          - ::1/128

    access_rules:
      local:
        allow: local
      c2s:
        deny: blocked
        allow: all

    shaper:
      normal:
        rate: 3000
        burst_size: 20000
      fast: 100000

    shaper_rules:
      max_user_sessions: 10
      max_user_offline_messages: 5000
      c2s_shaper:
        none: admin
        normal: all

    modules:
      mod_avatar: {}
      mod_blocking: {}
      mod_caps: {}
      mod_carboncopy: {}
      mod_client_state: {}
      mod_disco: {}
      mod_http_upload:
        host: "upload.${cfg.domain}"
        put_url: "https://${cfg.domain}:5443/upload"
        docroot: "/var/lib/ejabberd/upload"
        max_size: 104857600
      mod_last: {}
      mod_mam:
        assume_mam_usage: true
        default: always
      mod_offline:
        access_max_user_messages: max_user_offline_messages
      mod_ping: {}
      mod_privacy: {}
      mod_private: {}
      mod_pubsub:
        access_createnode: local
        plugins:
          - flat
          - pep
      mod_push: {}
      mod_push_keepalive: {}
      mod_roster:
        versioning: true
      mod_stream_mgmt:
        resend_on_timeout: if_offline
      mod_vcard: {}
      mod_vcard_xupdate: {}
      mod_version:
        show_os: false
  '';
in
{
  options.services.ejabberd-tailscale = {
    enable = mkEnableOption "a Tailscale-only ejabberd server";

    domain = mkOption {
      type = types.str;
      example = "host.example-tailnet.ts.net";
      description = "Tailscale MagicDNS name used as the XMPP domain and certificate name.";
    };

    tailscaleIPv4 = mkOption {
      type = types.str;
      example = "100.64.0.1";
      description = "Tailscale IPv4 address on which ejabberd listens.";
    };

    epmdPort = mkOption {
      type = types.port;
      default = 4370;
      description = "Loopback-only EPMD port reserved for ejabberd.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.tailscale.enable;
        message = "services.ejabberd-tailscale requires services.tailscale.enable";
      }
    ];

    services.ejabberd = {
      enable = true;
      configFile = "/etc/ejabberd/ejabberd.yml";
      ctlConfig = ''
        ERL_EPMD_PORT=${epmdPort}
        INET_DIST_INTERFACE=127.0.0.1
      '';
    };

    environment.etc."ejabberd/ejabberd.yml".source = ejabberdConfig;
    environment.etc."ejabberd/ejabberdctl.cfg".text = ''
      ERL_EPMD_ADDRESS=127.0.0.1
      ERL_EPMD_PORT=${epmdPort}
      INET_DIST_INTERFACE=127.0.0.1
    '';

    # The NixOS ejabberd module enables EPMD. Keep it on a dedicated loopback
    # port so personal Erlang sessions cannot collide with the system daemon.
    services.epmd.listenStream = "127.0.0.1:${epmdPort}";
    systemd.services.epmd.environment.ERL_EPMD_PORT = epmdPort;

    # Obtain and renew the tailnet's trusted certificate. The private key is
    # copied into ejabberd's private state directory and never enters the store.
    systemd.services.ejabberd-tailscale-cert = {
      description = "TLS certificate for Tailscale-only ejabberd";
      after = [
        "tailscaled.service"
        "tailscaled-autoconnect.service"
      ];
      wants = [ "tailscaled-autoconnect.service" ];
      requires = [ "tailscaled.service" ];
      before = [ "ejabberd.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        Restart = "on-failure";
        RestartSec = "30s";
        RuntimeDirectory = "ejabberd-cert";
        RuntimeDirectoryMode = "0700";
      };
      script = ''
        set -euo pipefail
        install -d -m 0700 -o ejabberd -g ejabberd ${tlsDir}
        ${config.services.tailscale.package}/bin/tailscale cert \
          --min-validity 720h \
          --cert-file "$RUNTIME_DIRECTORY/cert.pem" \
          --key-file "$RUNTIME_DIRECTORY/key.pem" \
          ${lib.escapeShellArg cfg.domain}
        install -m 0444 -o ejabberd -g ejabberd \
          "$RUNTIME_DIRECTORY/cert.pem" ${certFile}
        install -m 0400 -o ejabberd -g ejabberd \
          "$RUNTIME_DIRECTORY/key.pem" ${keyFile}
        if ${pkgs.systemd}/bin/systemctl --quiet is-active ejabberd.service; then
          ${pkgs.systemd}/bin/systemctl --no-block reload ejabberd.service
        else
          # A previous certificate failure also prevents ejabberd from starting.
          # Recover it after a later retry or timer run succeeds.
          ${pkgs.systemd}/bin/systemctl --no-block start ejabberd.service
        fi
      '';
    };

    systemd.timers.ejabberd-tailscale-cert = {
      description = "Renew ejabberd's Tailscale TLS certificate";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitActiveSec = "1d";
        RandomizedDelaySec = "1h";
        Unit = "ejabberd-tailscale-cert.service";
      };
    };

    systemd.services.ejabberd = {
      after = [ "ejabberd-tailscale-cert.service" ];
      requires = [ "ejabberd-tailscale-cert.service" ];
      environment.ERL_EPMD_PORT = epmdPort;
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/ejabberd/upload 0750 ejabberd ejabberd -"
    ];
  };
}
