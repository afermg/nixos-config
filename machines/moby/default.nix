# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}:
{
  # You can import other NixOS modules here
  imports = [
    # If you want to use modules from other flakes (such as nixos-hardware):
    # inputs.hardware.nixosModules.common-pc-ssd
    inputs.home-manager.nixosModules.home-manager

    # Import your generated (nixos-generate-config) hardware configuration
    # Disko configuration
    inputs.disko.nixosModules.disko
    ./disko.nix
    ../common/vm.nix
    # Path to make boot work with zstore pool
    ./hardware-configuration.nix

    # You can also split up your configuration and import pieces of it here:
    ./boot.nix
    ./overleaf.nix
    ./ejabberd.nix
    ./marimohub-connector.nix
    # ./marimohub.nix # Disabled: keep Overleaf's internal port 3000 free
    # ./hedgedoc.nix # This wasn't as useful
    # ./org-gcal.nix # Removed until we migrate over
    ../common/networking.nix
    ../common/printing.nix
    ../common/gpu/nvidia.nix
    ../common/substituters.nix
    ../common/pipewire.nix
    # ../common/virtualization.nix
    ../common/input_device.nix
    ../common/ssh.nix
    ../common/us_eng.nix
  ];

  # FHS
  programs.nix-ld.enable = true;

  services = {
    # systemd-resolved for DNS
    resolved = {
      enable = true;
      settings.Resolve = {
        domains = [ "~." ];
        DNSOverTLS = "true";
        dnssec = "true";
        fallbackDns = [
          "1.1.1.1#one.one.one.one"
          "1.0.0.1#one.one.one.one"
        ];
      };
    };

    # Desktop components
    desktopManager.gnome.enable = true;
    displayManager.gdm = {
      enable = true;
      autoSuspend = false;
    };

    # Enable the X11 windowing system.
    xserver = {
      enable = true;
      xkb.layout = "us";
    };

    # Ollama service
    ollama = {
      enable = true;
      package = pkgs.ollama-cuda;
      # acceleration = "cuda";
      environmentVariables = {
        CUDA_VISIBLE_DEVICES = "0";
        LD_LIBRARY_PATH = "${pkgs.cudaPackages.cudatoolkit}/lib:${pkgs.cudaPackages.cudatoolkit}/lib64";
      };
    };

    # Apache tika: Processs documents for LLM ingestion of PDFs
    # tika.enable = true;

    # Emacs: The one and only True Editor.
    emacs = {
      enable = true;
      startWithGraphical = true;
      # Xwidgets are not working # https://github.com/nix-community/emacs-overlay/issues/455
      package = pkgs.emacs.override {
        withImageMagick = true;
        withXwidgets = false;
      };
    };

    tailscale = {
      enable = true;
      authKeyFile = config.age.secrets.tailscale.path;
    };

  };

  nixpkgs = {
    # You can add overlays here
    overlays = builtins.attrValues outputs.overlays;
    # Configure your nixpkgs instance
    # config.allowUnfree = true;
  };

  # This will add each flake input as a registry
  # To make nix3 commands consistent with your flake
  nix.registry = (lib.mapAttrs (_: flake: { inherit flake; })) (
    (lib.filterAttrs (_: lib.isType "flake")) inputs
  );

  # This will additionally add your inputs to the system's legacy channels
  # Making legacy nix commands consistent as well, awesome!
  nix.nixPath = [ "/etc/nix/path" ];
  environment.etc = lib.mapAttrs' (name: value: {
    name = "nix/path/${name}";
    value.source = value.flake;
  }) config.nix.registry;

  nix.settings = {
    # Enable flakes and new 'nix' command
    experimental-features = "nix-command flakes";
    # Deduplicate and optimize nix store
    auto-optimise-store = true;
    # Leave enough pool headroom for stateful services such as MongoDB while
    # large closures (for example, TeX Live) are being realized.
    min-free = 20 * 1024 * 1024 * 1024;
    max-free = 50 * 1024 * 1024 * 1024;
  };

  fonts.packages = with pkgs; [
    emacs-all-the-icons-fonts
    font-awesome
    noto-fonts
    noto-fonts-color-emoji
    noto-fonts-cjk-sans
    liberation_ttf
    fira-code
    fira-code-symbols
    jetbrains-mono
    mplus-outline-fonts.githubRelease
    dina-font
    proggyfonts
    nerd-fonts.iosevka
  ];

  # Default system wide packages
  environment.systemPackages = pkgs.callPackage ../../modules/nixos/packages.nix { } ++ [
    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
  environment.shells = [
    pkgs.zsh
    pkgs.fish
  ];
  programs = {
    zsh.enable = true;
    fish.enable = true;

    # For blender
    steam = {
      enable = true;
      remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
      dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
      localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
    };
  };

  # Networking
  networking.hostName = "gpa85-cad";
  networking.hostId = "5a08e8de";
  # networking.bridges.br0.interfaces = [ "enp2s0" "wlp131s0" ];
  # enable the netbird service
  # services.netbird.enable = true;
  # environment.systemPackages = [ pkgs.netbird-ui ]; # for GUI

  # Users section, as a backup to the homes folder
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.amunoz = {
    shell = pkgs.fish;
    isNormalUser = true;
    initialPassword = "changeme";
    description = "Alan Munoz";
    extraGroups = [
      "networkmanager"
      "wheel"
      "libvirtd"
      "qemu-libvirtd"
      "input"
    ];
    openssh.authorizedKeys.keyFiles = [
      ../../homes/amunoz/id_ed25519.pub
    ];
  };

  users.users.hhakem = {
    shell = pkgs.zsh;
    isNormalUser = true;
    description = "Hugo Hakem";
    extraGroups = [
      "networkmanager"
      "wheel"
      "libvirtd"
      "qemu-libvirtd"
      "input"
    ];
    openssh.authorizedKeys.keyFiles = [
      ../../homes/hhakem/id_rsa.pub
    ];
  };

  users.users.zchen = {
    shell = pkgs.zsh;
    isNormalUser = true;
    description = "Zitong Chen";
    extraGroups = [
      "networkmanager"
      "wheel"
      "libvirtd"
      "qemu-libvirtd"
      "input"
    ];
    openssh.authorizedKeys.keyFiles = [
      ../../homes/zchen/id_rsa.pub
    ];
  };

  users.users.jfredinh = {
    shell = pkgs.fish;
    isNormalUser = true;
    description = "Johan Fredinh";
    extraGroups = [
      "networkmanager"
      "wheel"
      "libvirtd"
      "qemu-libvirtd"
      "input"
    ];
    openssh.authorizedKeys.keyFiles = [
      ../../homes/jfredinh/id_ed25519.pub
    ];
  };

  # Enable home-manager for users
  # home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = { inherit inputs outputs; };
  home-manager.backupFileExtension = "backups";

  # USER HOMES
  # home-manager.users.amunoz = import ../../modules/nixos/home-manager.nix;
  home-manager.users.amunoz = {
    dconf.settings = {
      "org/gnome/shell".favorite-apps = [
        "firefox.desktop"
        "emacsclient.desktop"
        "org.gnome.Nautilus.desktop"
        "com.mitchellh.ghostty.desktop"
      ];
      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0".command =
        lib.mkForce "ghostty";
    };

    imports = [
      # ../../modules/nixos/home-manager.nix;
      outputs.homeModules.amunoz
      ../../modules/shared/config/pi-msg/pi-msg.nix
      ../../modules/shared/config/syncthing/sync.nix
    ];
  };

  home-manager.users.hhakem = {
    imports = [
      inputs.agenix.homeManagerModules.default
      ../../homes/hhakem/moby.nix
    ];
  };

  home-manager.users.zchen = {
    imports = [
      inputs.agenix.homeManagerModules.default
      ../../homes/zchen/moby.nix
    ];
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "23.11";
}
