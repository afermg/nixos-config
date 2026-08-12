{
  config,
  lib,
  pkgs,
  piMsgInputs,
  ...
}:
let
  cfg = config.services.pi-msg;
  piMsgPkgs = piMsgInputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  ownerJid = "${cfg.ownerUsername}@${cfg.domain}";
  botJid = "${cfg.botUsername}@${cfg.domain}";
  configPath = "${config.xdg.configHome}/pi-msg/config.json";
  workspace = "${config.home.homeDirectory}/${cfg.workspaceDirectory}";

  # pi-msg requires Go 1.26.4, newer than some consuming system flakes.
  piMsg = piMsgPkgs.buildGoModule rec {
    pname = "pi-msg";
    version = "0.3.0";

    src = piMsgPkgs.fetchFromGitHub {
      owner = "zachpmanson";
      repo = "pi-msg";
      rev = "f97c9dd1cbba60fd56a1bbec35bf24cce41ab084";
      hash = "sha256-wQC+H+qz23b8Jn9gbnlBcILwBPMOGcWEwry5vFUHsy0=";
    };

    vendorHash = "sha256-9wjQDjRsdcuzuWMNar6BDtGWlbyqQUBY8mtv/I+zzU4=";

    meta = {
      description = "Bridge the Pi coding agent to XMPP";
      homepage = "https://github.com/zachpmanson/pi-msg";
      license = lib.licenses.mit;
      mainProgram = "pi-msg";
    };
  };

  validateConfig = pkgs.writeShellApplication {
    name = "pi-msg-check-config";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      set -euo pipefail

      config=${lib.escapeShellArg configPath}
      if ! jq -e \
        --arg jid ${lib.escapeShellArg botJid} \
        --arg owner ${lib.escapeShellArg ownerJid} \
        --arg service ${lib.escapeShellArg "${cfg.domain}:5222"} \
        --arg upload ${lib.escapeShellArg "upload.${cfg.domain}"} \
        --arg workdir ${lib.escapeShellArg workspace} \
        '.accounts.default as $account
          | ($account.jid == $jid)
          and ($account.owner == $owner)
          and ($account.service == $service)
          and ($account.uploadService == $upload)
          and ($account.workdir == $workdir)
          and ($account.password | type == "string" and length > 0)' \
        "$config" >/dev/null
      then
        echo "pi-msg config at $config does not match services.pi-msg settings" >&2
        exit 1
      fi
    '';
  };

  registerLocalAccounts = pkgs.writeShellApplication {
    name = "pi-msg-register-accounts";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      set -euo pipefail

      domain=${lib.escapeShellArg cfg.domain}
      config=${lib.escapeShellArg configPath}
      ctl=(
        sudo -u ejabberd env
        HOME=/var/lib/ejabberd
        ERL_EPMD_PORT=${toString cfg.ejabberdEpmdPort}
        /run/current-system/sw/bin/ejabberdctl
        --config /etc/ejabberd/ejabberd.yml
        --ctl-config /etc/ejabberd/ejabberdctl.cfg
        --spool /var/lib/ejabberd
        --logs /var/log/ejabberd
      )

      if ! systemctl --quiet is-active ejabberd.service; then
        echo "ejabberd is not running; deploy the NixOS configuration first" >&2
        exit 1
      fi
      if [[ ! -r "$config" ]]; then
        echo "pi-msg's agenix config is not available at $config" >&2
        exit 1
      fi

      read -r -s -p "New password for ${ownerJid}: " owner_password
      echo
      read -r -s -p "Repeat password: " owner_password_confirm
      echo
      if [[ -z "$owner_password" || "$owner_password" != "$owner_password_confirm" ]]; then
        echo "Passwords were empty or did not match" >&2
        exit 1
      fi

      ${validateConfig}/bin/pi-msg-check-config
      bot_password=$(jq -er '.accounts.default.password' "$config")

      set_password() {
        local user=$1 password=$2
        if "''${ctl[@]}" check_account "$user" "$domain" >/dev/null 2>&1; then
          "''${ctl[@]}" change_password "$user" "$domain" "$password"
          echo "Updated $user@$domain"
        else
          "''${ctl[@]}" register "$user" "$domain" "$password"
          echo "Created $user@$domain"
        fi
      }

      set_password ${lib.escapeShellArg cfg.ownerUsername} "$owner_password"
      set_password ${lib.escapeShellArg cfg.botUsername} "$bot_password"
      unset owner_password owner_password_confirm bot_password

      systemctl --user try-restart pi-msg.service || true
      echo
      echo "Accounts ready:"
      echo "  phone: ${ownerJid}"
      echo "  bot:   ${botJid}"
    '';
  };

  remoteRegistrationScript = pkgs.writeShellScript "pi-msg-register-remote-account" ''
    set -euo pipefail

    secret=$1
    user=$2
    domain=$3
    epmd_port=$4
    trap 'rm -f "$secret"' EXIT

    bot_password=$(<"$secret")
    ctl=(
      sudo -u ejabberd env
      HOME=/var/lib/ejabberd
      ERL_EPMD_PORT="$epmd_port"
      /run/current-system/sw/bin/ejabberdctl
      --config /etc/ejabberd/ejabberd.yml
      --ctl-config /etc/ejabberd/ejabberdctl.cfg
      --spool /var/lib/ejabberd
      --logs /var/log/ejabberd
    )

    if ! systemctl --quiet is-active ejabberd.service; then
      echo "ejabberd is not running on $(hostname)" >&2
      exit 1
    fi

    if "''${ctl[@]}" check_account "$user" "$domain" >/dev/null 2>&1; then
      "''${ctl[@]}" change_password "$user" "$domain" "$bot_password"
      echo "Updated $user@$domain"
    else
      "''${ctl[@]}" register "$user" "$domain" "$bot_password"
      echo "Created $user@$domain"
    fi
    unset bot_password
  '';

  registerRemoteAccount = pkgs.writeShellApplication {
    name = "pi-msg-register-accounts";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.openssh
    ];
    text = ''
      set -euo pipefail

      host=${lib.escapeShellArg cfg.registrationSshHost}
      config=${lib.escapeShellArg configPath}
      local_secret=$(mktemp)
      remote_dir=""

      cleanup() {
        rm -f "$local_secret"
        if [[ -n "$remote_dir" ]]; then
          ssh "$host" rm -rf -- "$remote_dir" >/dev/null 2>&1 || true
        fi
      }
      trap cleanup EXIT
      chmod 0600 "$local_secret"

      if [[ ! -r "$config" ]]; then
        echo "pi-msg's agenix config is not available at $config" >&2
        exit 1
      fi
      ${validateConfig}/bin/pi-msg-check-config
      jq -er '.accounts.default.password' "$config" > "$local_secret"

      remote_dir=$(ssh "$host" 'umask 077; mktemp -d')
      scp -q ${remoteRegistrationScript} "$host:$remote_dir/register.sh"
      scp -q "$local_secret" "$host:$remote_dir/password"

      printf -v remote_command 'bash %q %q %q %q %q' \
        "$remote_dir/register.sh" \
        "$remote_dir/password" \
        ${lib.escapeShellArg cfg.botUsername} \
        ${lib.escapeShellArg cfg.domain} \
        ${lib.escapeShellArg (toString cfg.ejabberdEpmdPort)}
      ssh -t "$host" "$remote_command"

      systemctl --user try-restart pi-msg.service || true
      echo
      echo "Accounts ready:"
      echo "  phone: ${ownerJid}"
      echo "  bot:   ${botJid}"
    '';
  };

  registrationHelper =
    if cfg.registerLocalAccounts then
      registerLocalAccounts
    else if cfg.registrationSshHost != null then
      registerRemoteAccount
    else
      null;
in
{
  options.services.pi-msg = {
    enable = mkEnableOption "the pi-msg XMPP bridge";

    domain = mkOption {
      type = types.str;
      example = "host.example-tailnet.ts.net";
      description = "XMPP domain used by the configured bot account.";
    };

    ownerUsername = mkOption {
      type = types.str;
      default = "alan";
      description = "Local part of the human owner's XMPP JID.";
    };

    botUsername = mkOption {
      type = types.str;
      default = "pi";
      description = "Local part of the bot's XMPP JID.";
    };

    secretFile = mkOption {
      type = types.path;
      description = "Age-encrypted pi-msg config.json whose account settings match this host.";
    };

    workspaceDirectory = mkOption {
      type = types.str;
      default = "Documents/pi";
      description = "Pi workspace directory, relative to the user's home directory.";
    };

    registerLocalAccounts = mkOption {
      type = types.bool;
      default = false;
      description = "Install the helper that registers the owner and bot in a local ejabberd.";
    };

    registrationSshHost = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "user@xmpp-host.example-tailnet.ts.net";
      description = "SSH host on which the helper should register only the bot account.";
    };

    ejabberdEpmdPort = mkOption {
      type = types.port;
      default = 4370;
      description = "Loopback EPMD port used by the local ejabberd instance.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(lib.hasPrefix "/" cfg.workspaceDirectory);
        message = "services.pi-msg.workspaceDirectory must be relative to the home directory";
      }
      {
        assertion = !(cfg.registerLocalAccounts && cfg.registrationSshHost != null);
        message = "services.pi-msg cannot use local and remote account registration together";
      }
    ];

    age.secrets.pi-msg = {
      file = cfg.secretFile;
      path = configPath;
      mode = "0600";
    };

    home.packages = [ piMsg ] ++ lib.optional (registrationHelper != null) registrationHelper;

    home.file."${cfg.workspaceDirectory}/AGENTS.md".text = ''
      # Remote Pi workspace

      This is the conservative default working directory for Pi sessions driven
      from a phone through pi-msg. The user's source repositories are under
      `~/.local/share/src`. Ask which repository to use before changing one when
      the request does not identify it clearly.

      A persistent Emacs server is normally available on this machine. Use the
      emacs-pair skill when the user asks to inspect, manipulate, or display live
      Emacs buffers. Avoid editing an open modified buffer directly on disk.
    '';

    systemd.user.services.pi-msg = {
      Unit = {
        Description = "XMPP bridge for the Pi coding agent";
        After = [
          "agenix.service"
          "network-online.target"
        ];
        Requires = [ "agenix.service" ];
      };
      Service = {
        ExecStartPre = "${validateConfig}/bin/pi-msg-check-config";
        ExecStart = "${piMsg}/bin/pi-msg";
        WorkingDirectory = workspace;
        Environment = [
          "PI_MSG_CONFIG=${configPath}"
          "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin"
        ];
        Restart = "on-failure";
        RestartSec = "10s";
        UMask = "0077";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
