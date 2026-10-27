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

  # Oppy joins the existing share without enrolling unrelated Broad projects.
  orgOnlyIgnorePatterns = [
    ".DS_Store"
    "**/.git"
    "**/.git/**"
    "**/.agent-shell"
    "**/.agent-shell/**"
    "**/.claude"
    "**/.claude/**"
    "**/.pi"
    "**/.pi/**"
    "**/.auto"
    "**/.auto/**"
    "**/.#*"
    "**/#*#"
    "**/*~"
    "!/org"
    "!/org/**"
    "*"
  ];

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
    "**/.auto"
    "**/.auto/**"
    "**/.#*"
    "**/#*#"
    "**/*~"
    # Keep Org attachments with their notes, not just text files.
    "!/org/**"
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
  imports = [ ./ix-backups.nix ];

  options.hindsightBackupSyncthing = {
    enable = lib.mkEnableOption "the Hindsight backup Syncthing peer";
    address = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Deprecated; ixBackupMesh binds to this host's Tailscale DNS name.";
    };
  };

  config = lib.mkIf enabled {
    ixBackupMesh = {
      enable = true;
    } // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      deviceName = if config.home.username == "alan" then "darwin001" else "darwin002";
    };

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
          (lib.mkIf (config.ixBackupMesh.deviceName == "oppy") {
            "broad-notes-drafts-text" = {
              id = "broad-notes-drafts-text";
              label = "Broad org notes and drafts text";
              path = "${config.home.homeDirectory}/Documents/broad";
              type = "sendreceive";
              devices = [ "darwin001" "darwin002" ];
              ignorePerms = true;
              fsWatcherEnabled = true;
              order = "smallestFirst";
              ignorePatterns = orgOnlyIgnorePatterns;
              versioning = {
                type = "staggered";
                params = { cleanInterval = "3600"; maxAge = "15552000"; };
              };
            };
          })
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
              devices = lib.filter (name: name != config.ixBackupMesh.deviceName)
                [ "moby" "oppy" "darwin001" "darwin002" ];
              ignorePerms = true;
              fsWatcherEnabled = true;
              ignorePatterns = broadNotesDraftsTextIgnorePatterns;
              versioning = {
                type = "staggered";
                params = { cleanInterval = "3600"; maxAge = "15552000"; };
              };
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

        # ixBackupMesh binds the listener to this host's Tailscale DNS name.
        options = {
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
