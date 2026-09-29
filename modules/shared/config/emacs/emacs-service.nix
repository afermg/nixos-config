{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.afm.emacsService;
  defaultPackage = pkgs.emacs.override {
    withImageMagick = true;
    withXwidgets = false; # https://github.com/nix-community/emacs-overlay/issues/466
  };
in
{
  options.afm.emacsService = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable the shared Emacs daemon service.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = "Emacs package used by Home Manager.";
    };

    extraPackages = lib.mkOption {
      type = lib.types.nullOr (lib.types.functionTo (lib.types.listOf lib.types.package));
      default = null;
      description = "Additional Emacs packages installed with the selected package.";
    };

    clientEnable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether Home Manager should install the emacsclient wrapper.";
    };

    restart = lib.mkOption {
      type = lib.types.str;
      default = "always";
      description = "systemd restart policy for the user Emacs service.";
    };

    restartSec = lib.mkOption {
      type = lib.types.str;
      default = "5s";
      description = "Delay before restarting the user Emacs service.";
    };

    timeoutStartSec = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional startup timeout for slower daemon profiles.";
    };

    startLimitIntervalSec = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Optional systemd start-limit interval for the user service.";
    };

    startLimitBurst = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Optional systemd start-limit burst for the user service.";
    };

    initFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
      default = null;
      description = "Optional Emacs init file linked into ~/.emacs.d/init.el.";
    };

    earlyInitFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
      default = null;
      description = "Optional Emacs early-init file linked into ~/.emacs.d/early-init.el.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.emacs = lib.mkMerge [
      {
        enable = true;
        package = cfg.package;
      }
      (lib.mkIf (cfg.extraPackages != null) {
        extraPackages = cfg.extraPackages;
      })
    ];

    services.emacs = {
      enable = true;
      startWithUserSession = true;
      client.enable = cfg.clientEnable;
    };

    systemd.user.services.emacs = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit = lib.mkMerge [
        (lib.mkIf (cfg.startLimitIntervalSec != null) {
          StartLimitIntervalSec = cfg.startLimitIntervalSec;
        })
        (lib.mkIf (cfg.startLimitBurst != null) {
          StartLimitBurst = cfg.startLimitBurst;
        })
      ];
      Service = lib.mkMerge [
        {
          Restart = lib.mkForce cfg.restart;
          RestartSec = cfg.restartSec;
        }
        (lib.mkIf (cfg.timeoutStartSec != null) {
          TimeoutStartSec = cfg.timeoutStartSec;
        })
      ];
    };

    home.file = lib.mkMerge [
      (lib.mkIf (cfg.earlyInitFile != null) {
        ".emacs.d/early-init.el".source = config.lib.file.mkOutOfStoreSymlink (toString cfg.earlyInitFile);
      })
      (lib.mkIf (cfg.initFile != null) {
        ".emacs.d/init.el".source = config.lib.file.mkOutOfStoreSymlink (toString cfg.initFile);
      })
    ];
  };
}
