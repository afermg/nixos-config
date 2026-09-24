# Syncthing folders shared with moby over direct Tailscale DNS names.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hindsightBackupSyncthing;
  darwinUsers = [
    "alan"
    "amunozgo"
  ];
  enabled =
    cfg.enable || (pkgs.stdenv.hostPlatform.isDarwin && builtins.elem config.home.username darwinUsers);

  broadNotesDraftsTextIgnorePatterns = [
    ".DS_Store"
    "**/.DS_Store"
    ".sync-conflict-*"
    "**/.sync-conflict-*"
    ".syncthing.*.tmp"
    "**/.syncthing.*.tmp"
    ".git"
    ".git/**"
    "**/.git"
    "**/.git/**"
    "**/.agent-shell"
    "**/.agent-shell/**"
    "**/.claude"
    "**/.claude/**"
    "**/.pi"
    "**/.pi/**"
    "**/.ruff_cache"
    "**/.ruff_cache/**"
    "**/.venv"
    "**/.venv/**"
    "**/__pycache__"
    "**/__pycache__/**"
    "**/node_modules"
    "**/node_modules/**"
    "result"
    "result/**"
    "**/result"
    "**/result/**"
    "*.pdf"
    "**/*.pdf"
    "*.png"
    "**/*.png"
    "*.jpg"
    "**/*.jpg"
    "*.jpeg"
    "**/*.jpeg"
    "*.gif"
    "**/*.gif"
    "*.webp"
    "**/*.webp"
    "*.tif"
    "**/*.tif"
    "*.tiff"
    "**/*.tiff"
    "*.heic"
    "**/*.heic"
    "*.mp4"
    "**/*.mp4"
    "*.mov"
    "**/*.mov"
    "*.zip"
    "**/*.zip"
    "*.tar"
    "**/*.tar"
    "*.tar.gz"
    "**/*.tar.gz"
    "*.tgz"
    "**/*.tgz"
    "*.doc"
    "**/*.doc"
    "*.docx"
    "**/*.docx"
    "*.xls"
    "**/*.xls"
    "*.xlsx"
    "**/*.xlsx"
    "*.ppt"
    "**/*.ppt"
    "*.pptx"
    "**/*.pptx"
    "*.key"
    "**/*.key"
    "*.pages"
    "**/*.pages"
    "*.numbers"
    "**/*.numbers"
    "*.duckdb"
    "**/*.duckdb"
    "*.sqlite"
    "**/*.sqlite"
    "*.sqlite3"
    "**/*.sqlite3"
    "*.db"
    "**/*.db"
    "*.h5"
    "**/*.h5"
    "*.hdf5"
    "**/*.hdf5"
    "*.parquet"
    "**/*.parquet"
    "/admin"
    "/admin/**"
    "/bibliography"
    "/bibliography/**"
    "/learn"
    "/learn/**"
    "/mtg"
    "/mtg/**"
    "/projects"
    "/projects/**"
    "/resources"
    "/resources/**"
    "/scratch"
    "/scratch/**"
    "/tmp"
    "/tmp/**"
    "/website"
    "/website/**"
    "/drafts/admin_applications"
    "/drafts/admin_applications/**"
    "/drafts/_resources"
    "/drafts/_resources/**"
    "/nohup.out"
  ];
in
{
  options.hindsightBackupSyncthing = {
    enable = lib.mkEnableOption "the Hindsight backup Syncthing peer";
    address = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Deprecated; Syncthing now listens on tcp://:22000 and peers dial Tailscale DNS names.";
    };
  };

  config = lib.mkIf enabled {
    services.syncthing = {
      enable = true;
      guiAddress = "127.0.0.1:8384";

      # Keep folders and devices owned by other configuration intact.
      overrideDevices = false;
      overrideFolders = false;

      settings = {
        devices."moby" = {
          id = "IBGBMDU-WRH5ECV-YS3BFJ7-EPJPC5X-HVLGWGA-RUIFYSG-Y2BOQKO-MNPHHQ4";
          addresses = [ "tcp://moby.tail5e510f.ts.net:22000" ];
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

            "broad-notes-drafts-text" = {
              id = "broad-notes-drafts-text";
              label = "Broad org notes and drafts text";
              path = "${config.home.homeDirectory}/Documents/broad";
              type = "sendreceive";
              devices = [ "moby" ];
              ignorePerms = true;
              fsWatcherEnabled = true;
              ignorePatterns = broadNotesDraftsTextIgnorePatterns;
            };
          })
          (lib.mkIf
            (
              pkgs.stdenv.hostPlatform.isDarwin
              && builtins.elem config.home.username [
                "alan"
                "amunozgo"
              ]
            )
            {
              "purdue-h1b-i9-preparation" = {
                id = "purdue-h1b-i9-preparation";
                label = "Purdue H-1B I-9 preparation";
                path = "${config.home.homeDirectory}/Documents/broad/drafts/admin_applications/purdue_h1b/i9_preparation";
                type = "sendreceive";
                devices = [ "moby" ];
                ignorePerms = true;
                fsWatcherEnabled = true;
              };
            }
          )
        ];

        # Peers are addressed through Tailscale DNS; listeners avoid pinning a
        # tailnet IP so MagicDNS reassignments do not require configuration edits.
        options = {
          listenAddresses = [ "tcp://:22000" ];
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
