{
  config,
  pkgs,
  inputs,
  outputs,
  lib,
  user ? "alan",
  ...
}:
let
  myEmacsLauncher = pkgs.writeScript "emacs-launcher.command" ''
    #!/bin/sh
    emacsclient -c -n &
  '';
  disabledCtrlSpaceHotkey = lib.generators.toPlist { escape = true; } {
    enabled = false;
    value = {
      parameters = [
        32
        49
        262144
      ];
      type = "standard";
    };
  };
in
{
  imports = [
    #../../modules/darwin/home-manager.nix
    # ../../modules/shared
    # ../../modules/shared/cachix
    inputs.home-manager.darwinModules.home-manager
    inputs.nix-homebrew.darwinModules.nix-homebrew
    (import ../common/nix-homebrew.nix {
      inherit inputs;
      user = "${user}";
    })
    ../common/nix.nix
    ../common/substituters.nix
    ./dock
    ../../modules/darwin/aerospace.nix
  ];

  services = {
    # Auto upgrade nix package and the daemon service.
    tailscale.enable = true; # Network of devices
  };

  # Setup user, packages, programs
  nix = {
    settings.trusted-users = [
      "@admin"
      "${user}"
    ];
    enable = false; # determinate systems nix conflicts with nix
    optimise.automatic = lib.mkForce false;
    gc.automatic = lib.mkForce false;

    # Turn this on to make command line easier
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  # Determinate Nix manages /etc/nix/nix.conf and ignores nix.settings above
  # (since nix.enable = false). Write Determinate-specific settings into the
  # companion file that /etc/nix/nix.conf loads via `!include nix.custom.conf`.
  environment.etc."nix/nix.custom.conf".text = ''
    trusted-users = root @admin ${user}
    lazy-trees = true
  '';

  # Turn off NIX_PATH warnings now that we're using flakes
  system.checks.verifyNixPath = false;
  security.pam.services.sudo_local.touchIdAuth = true;

  fonts = {
    packages = [
      pkgs.dejavu_fonts
      pkgs.nerd-fonts.iosevka
      # pkgs.nerdfonts
    ];
  };

  # Load configuration that is shared across systems
  environment.systemPackages = with pkgs; [
    emacs
    (pkgs.writeShellScriptBin "glibtool" "exec ${pkgs.libtool}/bin/libtool $@")
  ]; # ++ (import ../../modules/shared/packages.nix { inherit pkgs; });

  system = {
    # Turn off NIX_PATH warnings now that we're using flakes
    stateVersion = 4;

    defaults = {
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        ApplePressAndHoldEnabled = false;

        # 120, 90, 60, 30, 12, 6, 2
        KeyRepeat = 2;

        # 120, 94, 68, 35, 25, 15
        InitialKeyRepeat = 15;

        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.sound.beep.volume" = 0.0;
        "com.apple.sound.beep.feedback" = 0;
      };

      dock = {
        autohide = true;
        show-recents = false;
        launchanim = true;
        orientation = "left";
        tilesize = 48;
      };

      finder = {
        _FXShowPosixPathInTitle = false;
      };

      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
      };
    };

    # Disable "Select the previous input source" without replacing other shortcuts.
    activationScripts.userDefaults.text = lib.mkAfter ''
      echo >&2 "Disabling the macOS Ctrl-Space input source shortcut..."
      /bin/launchctl asuser "$(/usr/bin/id -u -- ${lib.escapeShellArg user})" \
        /usr/bin/sudo --user=${lib.escapeShellArg user} -- \
        /usr/bin/defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys \
          -dict-add 60 ${lib.escapeShellArg disabledCtrlSpaceHotkey}
    '';
  };

  # Configure nixpkgs
  nixpkgs = {
    # You can add overlays here
    overlays = builtins.attrValues outputs.overlays;
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
    };
  };

  # Create users
  users.users.${user} = {
    description = "Alan Munoz";

    home = "/Users/${user}";
    createHome = true;
    isHidden = false;
    #initialPassword = "password";
    shell = pkgs.fish;
    openssh.authorizedKeys.keyFiles = [
      ../../homes/amunoz/id_ed25519.pub
    ];
  };
  system.primaryUser = "${user}";
  programs.fish.enable = true;

  # Configure homebrew
  homebrew = {
    enable = true;
    # brews = ["input-leap"]; # Example of brew
    brews = [
      # Here we add any formulae (e.g., https://formulae.brew.sh/formula/portaudio)
    ];
    taps = map (key: builtins.replaceStrings [ "homebrew-" ] [ "" ] key) (
      builtins.attrNames config.nix-homebrew.taps
    );
    casks = pkgs.callPackage ./casks.nix { };
    onActivation = {
      cleanup = "uninstall";
      autoUpdate = true;
      upgrade = true;
    };
  };

  # Configure home manager
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit inputs outputs;
      amunozInputs = inputs;
      username = user;
    };
    users.${user} = {
      imports = [
        inputs.agenix.homeManagerModules.default
        ../../homes/amunoz/home.nix
      ];
      home = {
        packages = pkgs.callPackage ../../modules/darwin/packages.nix { inherit inputs; };
      };
      programs = {
        # This is important! Removing this will break your shell and thus your system
        # This is needed even if you enable zsh in home manager
        zsh.enable = true;
        fish.enable = true;
        wezterm.enable = true;
      }
      // import ../../modules/shared/home-manager.nix {
        inherit
          config
          pkgs
          lib
          user
          ;
      };
    };
    backupFileExtension = "bak";
  };

  local.aerospace = {
    enable = true;
    username = user;
  };

  # Fully declarative dock using the latest from Nix Store
  local.dock = {
    enable = true;
    username = user;
    entries = [
      { path = "${pkgs.firefox}/Applications/Firefox.app/"; }
      { path = "${pkgs.zotero}/Applications/Zotero.app/"; }
      { path = "${pkgs.wezterm}/Applications/Wezterm.app/"; }
      {
        path = toString myEmacsLauncher;
        section = "others";
      }
      {
        path = "${config.users.users.${user}.home}/.local/share/";
        section = "others";
        options = "--sort name --view grid --display folder";
      }
      {
        path = "${config.users.users.${user}.home}/Downloads";
        section = "others";
        options = "--sort name --view grid --display stack";
      }
    ];
  };
  # remap keys : Caps -> Esc
  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToEscape = true;

  # Disable press and hold for diacritics.
  # I want to be able to press and hold j and k
  # in vim to move around.
  # system.defaults.NSGlobalDomain.ApplePressAndHoldEnabled = false;
}
