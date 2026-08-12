# Private Syncthing folders shared from moby over direct Tailscale links.
# This module is imported only by the amunoz@moby Home Manager configuration.
{ ... }:
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
          addresses = [ "tcp://100.72.120.59:22000" ];
          autoAcceptFolders = false;
        };
        darwin002 = {
          id = "TKXRRWK-K5EDNVM-AVXZKCP-TE2M2LC-A7CYJB7-LY2G5MU-EYGHIZC-I6GMRAR";
          addresses = [ "tcp://100.110.180.8:22000" ];
          autoAcceptFolders = false;
        };
        oppy = {
          id = "WUGSSP7-XBIOCPG-3JTGPIV-JSW4GFC-Z3U66BN-CZKTYC3-ADTX2IO-TG3DIQZ";
          addresses = [ "tcp://100.79.40.39:22000" ];
          autoAcceptFolders = false;
        };
        spirit = {
          id = "2FPYDCN-NOTA4ZH-VCEORYQ-YL5NUUU-VCL3PXZ-DFMV7GR-DPN6PG5-Y7TPAAX";
          addresses = [ "tcp://100.126.147.16:22000" ];
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

      # Use only the direct Tailscale path: no LAN/global discovery, NAT, or relays.
      options = {
        listenAddresses = [ "tcp://100.94.5.85:22000" ];
        globalAnnounceEnabled = false;
        localAnnounceEnabled = false;
        relaysEnabled = false;
        natEnabled = false;
        urAccepted = -1;
      };
    };
  };
}
