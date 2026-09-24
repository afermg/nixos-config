# Private Syncthing folders shared from moby over direct Tailscale links.
# This module is imported only by the amunoz@moby Home Manager configuration.
{ ... }:

let
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
  services.syncthing = {
    enable = true;
    guiAddress = "127.0.0.1:8384";

    # No devices or folders configured interactively may persist.
    overrideDevices = true;
    overrideFolders = true;

    settings = {
      devices = {
        darwin001 = {
          id = "HQRQ26I-ZMMDORA-B6QCPZK-VDOCWAJ-JNXBONT-Z2TRSUL-V4U2PZT-ZHBFHQV";
          addresses = [ "tcp://alan-purdue-mbp.tail5e510f.ts.net:22000" ];
          autoAcceptFolders = false;
        };
        darwin002 = {
          id = "OXQSPCP-XFPIUK7-QB646U3-YE5ZHIW-6WIPG36-G3PWKBE-FEIXCB6-ZUFAOAN";
          addresses = [ "tcp://wm9e9-3f5.tail5e510f.ts.net:22000" ];
          autoAcceptFolders = false;
        };
        oppy = {
          id = "WUGSSP7-XBIOCPG-3JTGPIV-JSW4GFC-Z3U66BN-CZKTYC3-ADTX2IO-TG3DIQZ";
          addresses = [ "tcp://oppy.tail5e510f.ts.net:22000" ];
          autoAcceptFolders = false;
        };
        spirit = {
          id = "2FPYDCN-NOTA4ZH-VCEORYQ-YL5NUUU-VCL3PXZ-DFMV7GR-DPN6PG5-Y7TPAAX";
          addresses = [ "tcp://spirit.tail5e510f.ts.net:22000" ];
          autoAcceptFolders = false;
        };
      };

      folders."sync" = {
        id = "sync";
        label = "Sync";
        path = "/home/amunoz/sync";
        type = "sendreceive";
        devices = [
          "darwin001"
          "darwin002"
        ];
        ignorePerms = true;
        fsWatcherEnabled = true;
        ignorePatterns = [ ];
      };

      folders."private-docs-01" = {
        id = "private-docs-01";
        label = "Private Docs 01";
        path = "/home/amunoz/.local/share/syncthing/private-docs-01";
        type = "sendreceive";
        devices = [
          "darwin001"
          "darwin002"
        ];
        ignorePerms = true;
        fsWatcherEnabled = true;
        ignorePatterns = [ ];
      };

      folders."broad-notes-drafts-text" = {
        id = "broad-notes-drafts-text";
        label = "Broad org notes and drafts text";
        path = "/home/amunoz/Documents/broad";
        type = "sendreceive";
        devices = [
          "darwin001"
          "darwin002"
        ];
        ignorePerms = true;
        fsWatcherEnabled = true;
        ignorePatterns = broadNotesDraftsTextIgnorePatterns;
      };

      folders."purdue-h1b-i9-preparation" = {
        id = "purdue-h1b-i9-preparation";
        label = "Purdue H-1B I-9 preparation";
        path = "/home/amunoz/Documents/broad/drafts/admin_applications/purdue_h1b/i9_preparation";
        type = "sendreceive";
        devices = [
          "darwin001"
          "darwin002"
        ];
        ignorePerms = true;
        fsWatcherEnabled = true;
        ignorePatterns = [ ];
      };

      folders."hindsight-backups" = {
        id = "hindsight-backups";
        label = "Hindsight encrypted backups";
        path = "/home/amunoz/.local/share/syncthing/hindsight-backups";
        type = "sendreceive";
        devices = [
          "darwin001"
          "darwin002"
          "oppy"
          "spirit"
        ];
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
}
