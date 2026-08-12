{
  pkgs,
  config,
  inputs,
  amunozInputs ? inputs,
  username ? null,
  ...
}:
let
  user = if pkgs.stdenv.isLinux then "amunoz" else (if username != null then username else "alan");
  home_parent = if pkgs.stdenv.isLinux then "home" else "Users";
  atuin_daemon_p = if pkgs.stdenv.isLinux then true else false;
  personalPkgs = amunozInputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  personalAtuin = personalPkgs.atuin;
in
{
  # nixpkgs.{config,overlays} and the agenix home-manager module are injected
  # by `homeModules.amunoz` in flake.nix. `amunozInputs` keeps this profile's
  # package pins authoritative even when a consuming flake passes its own
  # generic `inputs` through Home Manager's extraSpecialArgs.
  home = {
    username = "${user}";
    homeDirectory = "/${home_parent}/${user}";
    stateVersion = "24.05";
    packages = pkgs.callPackage ./packages.nix { inputs = amunozInputs; } ++ [
      # Recover atuin sync after server-side session invalidation. Reads
      # username/password from rbw's "atuin" entry and the BIP39 key from
      # the "atuin key" entry, then runs `atuin login`.
      (pkgs.writeShellApplication {
        name = "atuin-relogin";
        runtimeInputs = [
          personalAtuin
          pkgs.rbw
        ];
        text = ''
          set -euo pipefail
          rbw unlock
          user=$(rbw get atuin --field username)
          pass=$(rbw get atuin)
          key=$(rbw get 'atuin key')
          atuin login -u "$user" -p "$pass" -k "$key"
        '';
      })
    ];
    file = import ../../modules/shared/files.nix { inherit config pkgs; };
  };

  age = {
    identityPaths = [ "/${home_parent}/${user}/.ssh/id_ed25519" ];
    secrets.atuin = {
      file = ../../secrets/atuin.age;
      path = "${config.home.homeDirectory}/.local/share/atuin/key";
    };
  };
  # Gnome graphical interface
  dconf.settings = {
    "org/gnome/settings-daemon/plugins/power" = {
      sleep-inactive-ac-type = "nothing";
    };
    "org/gnome/desktop/input-sources" = {
      xkb-options = [ "caps:swapescape" ];
    };
    "org/gnome/shell".enabled-extensions = [
      "forge@jmmaranan.com"
      "appindicatorsupport@rgcjonas.gmail.com"
    ];
    # Custom keybindings
    "org/gnome/desktop/wm/keybindings" = {
      activate-window-menu = "disabled";
      toggle-message-tray = "disabled";
      minimize = [ ];
      move-to-monitor-left = [ ];
      move-to-monitor-right = [ ];
      hide-window = [ ];
      close = [ "<Super>q" ];
      move-to-workspace-1 = [ "<Shift><Super>1" ];
      move-to-workspace-2 = [ "<Shift><Super>2" ];
      move-to-workspace-3 = [ "<Shift><Super>3" ];
      move-to-workspace-4 = [ "<Shift><Super>4" ];
      move-to-workspace-left = [ "<Control><Shift><Super>h" ];
      move-to-workspace-right = [ "<Control><Shift><Super>l" ];
      switch-to-workspace-1 = [ "<Super>1" ];
      switch-to-workspace-2 = [ "<Super>2" ];
      switch-to-workspace-3 = [ "<Super>3" ];
      switch-to-workspace-4 = [ "<Super>4" ];
      switch-to-workspace-left = [ "<Shift><Control>h" ];
      switch-to-workspace-right = [ "<Shift><Control>l" ];
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      # binding = "<Super>Return"; # conflicts with forge, see  https://github.com/forge-ext/forge/issues/37
      binding = "<Shift><Alt>t";
      command = "wezterm";
      name = "Terminal";
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1" = {
      binding = "<Super>w";
      command = "/usr/bin/env firefox";
      name = "Firefox";
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2" = {
      binding = "<Super>e";
      command = "/usr/bin/env emacsclient -c -a emacs";
      name = "Emacs";
    };
    "org/gnome/settings-daemon/plugins/media-keys".custom-keybindings = [
      "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
      "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/"
    ];
  };

  imports = [
    ../../modules/shared/config/emacs/emacs-service.nix
    ../../modules/shared/config/opencode/opencode.nix
    ../../modules/shared/config/claude/claude.nix
    ../../modules/shared/config/codex/codex.nix
    ../../modules/shared/config/pi/pi.nix
    ../../modules/shared/config/syncthing/receiver.nix
    ../../modules/shared/config/email/rbw.nix
    ../../modules/shared/config/harper/harper.nix
  ];

  programs.atuin = {
    enable = true;
    package = personalAtuin;
    enableFishIntegration = true;
    daemon.enable = atuin_daemon_p;
    flags = [ "--disable-up-arrow" ];
    settings = {
      auto_sync = true;
      sync_frequency = "5m";
      sync_address = "https://api.atuin.sh";
      search_mode = "prefix";
    };
  };

  # Ensure the agenix-decrypted key file is mounted before atuin starts. Without
  # this ordering, atuin's load_key() can see a broken symlink, fall through to
  # new_key(), and write a fresh random key — encrypting subsequent records
  # under a key nobody else has. (Source of the 1Mup orphan records of 2026-04.)
  systemd.user.services = pkgs.lib.mkIf atuin_daemon_p {
    atuin-daemon.Unit.After = [ "agenix.service" ];
    atuin-daemon.Unit.Requires = [ "agenix.service" ];
  };

  programs.fish = {
    enable = true;
    plugins = [
      # Enable a plugin (here grc for colorized command output) from nixpkgs
      {
        name = "pure";
        src = pkgs.fishPlugins.pure.src;
      }
      {
        name = "autopair";
        src = pkgs.fishPlugins.autopair.src;
      }
      {
        name = "fishbang";
        src = pkgs.fishPlugins.fishbang.src;
      }
      {
        name = "fish-you-should-use";
        src = pkgs.fishPlugins.fish-you-should-use.src;
      }
      {
        name = "sponge";
        src = pkgs.fishPlugins.sponge.src;
      }
      {
        name = "async-prompt";
        src = pkgs.fishPlugins.async-prompt.src;
      }
      # Incompatible with async
      # {
      #   name = "transient-fish";
      #   src = pkgs.fishPlugins.transient-fish.src;
      # }
    ];
    # Atuin+fzf history from https://github.com/atuinsh/atuin/issues/68
    interactiveShellInit = ''
      set --universal pure_enable_nixdevshell true

      # Ation + fzf
      function fzf_history
          set -l line (commandline)

          # tac reverses order initially, tiebreak sorts(?), -n2..,.. ignores first two fields, +m means no "--multi"
          set -l result (atuin search --cmd-only | fzf --tac "-n2..,.." --tiebreak=index "+m" --query="$line")

          set -l key $result[1]
          set -l selected $result[2]

          if test "$key" = enter
              commandline --replace $selected
              commandline -f repaint
              commandline -f execute
              return
          end

          if test -n "$selected"
              commandline -r -- $selected
          end

          commandline -f repaint
      end
      set -gx FZF_DEFAULT_OPTS "--bind=alt-k:up,alt-j:down --expect=tab,enter --layout=reverse 
        --height=17 --delimiter='\t' --with-nth=1 
          --preview-window='border-rounded' --prompt='  ' --marker=' ' --pointer=' ' 
          --separator='─' --scrollbar='┃' --layout='reverse' 
        "
      set -x ATUIN_NOBIND true
      bind \cR fzf_history
    '';
  };

  # SMTP: port 587 is blackholed on this network (TCP accepts but no banner
  # arrives, hangs on recvfrom), so both accounts use 465 / implicit TLS.
  programs.msmtp.enable = true;
  accounts.email = {
    maildirBasePath = ".mail";
    accounts = {
      quasimorphic = {
        primary = true;
        realName = "Alán F. Muñoz";
        address = "alan@quasimorphic.com";
        userName = "alan@quasimorphic.com";
        passwordCommand = [
          "rbw"
          "get"
          "'Quasimorphic Email'"
        ];
        smtp = {
          host = "witcher.mxrouting.net";
          port = 465;
          tls.useStartTls = false;
        };
        msmtp.enable = true;
      };
      broad = {
        realName = "Alán F. Muñoz";
        address = "amunozgo@broadinstitute.org";
        userName = "amunozgo@broadinstitute.org";
        passwordCommand = [
          "rbw"
          "get"
          "'Broad Email App Password'"
        ];
        smtp = {
          host = "smtp.gmail.com";
          port = 465;
          tls.useStartTls = false;
        };
        msmtp.enable = true;
      };
    };
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
    signing.format = "openpgp";
    settings = {
      user.name = "Alán F. Muñoz";
      user.email = "afer.mg@gmail.com";
      commit.gpgsign = true;
      gpg.format = "ssh";
      gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";
      user.signingkey = "~/.ssh/id_ed25519.pub";
      # HTTPS auth for the self-hosted Overleaf git-bridge and the
      # hosted overleaf.com git-bridge. Tokens live in ~/.netrc,
      # materialized by agenix from secrets/netrc-overleaf.age at
      # activation. Scoped per-URL so GitHub HTTPS / other remotes are
      # untouched, and SSH-based git is unaffected (different code path
      # entirely).
      credential."https://overleaf.quasimorphic.com".helper = "netrc";
      credential."https://git.overleaf.com".helper = "netrc";
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.wezterm = {
    enable = true;
    extraConfig = builtins.readFile ../../modules/shared/config/wezterm/wezterm.lua;
  };
}
