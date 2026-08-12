# Syncthing folders shared with moby over direct Tailscale addresses.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hindsightBackupSyncthing;
  darwinAddresses = {
    alan = "100.72.120.59"; # darwin001 / alan-purdue-mbp
    amunozgo = "100.110.180.8"; # darwin002 / sce-bio-c06399
  };
  darwinAddress = darwinAddresses.${config.home.username} or null;
  receiverAddress = if cfg.enable then cfg.address else darwinAddress;
  enabled = cfg.enable || (pkgs.stdenv.hostPlatform.isDarwin && darwinAddress != null);
in
{
  options.hindsightBackupSyncthing = {
    enable = lib.mkEnableOption "the Hindsight backup Syncthing peer";
    address = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "This host's Tailscale IPv4 address.";
    };
  };

  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = receiverAddress != "";
        message = "hindsightBackupSyncthing.address must be set";
      }
    ];

    services.syncthing = {
      enable = true;
      guiAddress = "127.0.0.1:8384";

      # Keep folders and devices owned by other configuration intact.
      overrideDevices = false;
      overrideFolders = false;

      settings = {
        devices."moby" = {
          id = "IBGBMDU-WRH5ECV-YS3BFJ7-EPJPC5X-HVLGWGA-RUIFYSG-Y2BOQKO-MNPHHQ4";
          addresses = [ "tcp://100.94.5.85:22000" ];
          autoAcceptFolders = false;
        };

        folders = lib.mkMerge [
          {
            "hindsight-backups" = {
              id = "hindsight-backups";
              label = "Hindsight encrypted backups";
              path = "${config.home.homeDirectory}/.local/share/syncthing/hindsight-backups";
              type = "sendreceive";
              devices = [ "moby" ];
              ignorePerms = true;
              fsWatcherEnabled = true;
              versioning = {
                type = "staggered";
                params = {
                  cleanInterval = "3600";
                  maxAge = "15552000";
                };
              };
            };
          }
          (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
            "sync" = {
              id = "sync";
              label = "Sync";
              path = "${config.home.homeDirectory}/sync";
              type = "sendreceive";
              devices = [ "moby" ];
              ignorePerms = true;
              fsWatcherEnabled = true;
            };

            "private-docs-01" = {
              id = "private-docs-01";
              label = "Private Docs 01";
              path = "${config.home.homeDirectory}/.local/share/syncthing/private-docs-01";
              type = "sendreceive";
              devices = [ "moby" ];
              ignorePerms = true;
              fsWatcherEnabled = true;
            };
          })
        ];

        options = {
          listenAddresses = [ "tcp://${receiverAddress}:22000" ];
          globalAnnounceEnabled = false;
          localAnnounceEnabled = false;
          relaysEnabled = false;
          natEnabled = false;
          urAccepted = -1;
        };
      };
    };
  };
}
