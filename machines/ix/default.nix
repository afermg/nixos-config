# ix: independent headless Pi. See MAINTENANCE_LOG.md for deployment evidence.
{ inputs, pkgs, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    ../../modules/nixos/arm-emulation.nix
    ./hardware.nix
    ./direct-boot.nix
    ./ejabberd.nix
    ./hindsight.nix
    ./services.nix
  ];

  nixpkgs.hostPlatform = "aarch64-linux";
  networking.hostName = "ix";
  networking.useDHCP = true;
  networking.firewall.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitEmptyPasswords = false;
    };
  };
  services.tailscale.enable = true; # Enrol separately; never clone a node identity.
  services.timesyncd.enable = true;
  services.fstrim.enable = false; # WD bridge rejected WRITE SAME/DISCARD in testing.
  services.journald.settings.Journal.SystemMaxUse = "256M";

  programs.fish.enable = true;
  users.users.amunoz = {
    isNormalUser = true;
    shell = pkgs.fish;
    description = "Alán F. Muñoz";
    extraGroups = [ "wheel" ];
    linger = true;
    openssh.authorizedKeys.keyFiles = [ ../../homes/amunoz/id_ed25519.pub ];
  };
  # Existing key-only Pi administration policy; does not affect moby.
  security.sudo.wheelNeedsPassword = false;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    backupFileExtension = "ix-before-hm";
    users.amunoz = import ../../homes/ix/home.nix;
  };

  environment.systemPackages = with pkgs; [
    git
    rsync
    tmux
    curl
    htop
    btop
    pciutils
    usbutils
    python3
  ];
  nix.armEmulation.enable = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    max-jobs = 2;
    cores = 2;
    # This account is already the key-only, passwordless-wheel administrator.
    trusted-users = [
      "root"
      "amunoz"
    ];
  };
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "1G";
  system.stateVersion = "26.05";
}
