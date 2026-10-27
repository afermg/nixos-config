# Only encrypted, closed backup artifacts belong here; never live HA databases.
{ config, lib, ... }:
let
  cfg = config.ixBackupMesh;
  peers = {
    ix = {
      id = "6A43C2Q-EXU3MFI-U6N5DYC-L5X4NDW-QINTCUP-HWDUZNU-22BQLMY-ZSCP6QP";
      host = "ix.tail5e510f.ts.net";
    };
    moby = {
      id = "IBGBMDU-WRH5ECV-YS3BFJ7-EPJPC5X-HVLGWGA-RUIFYSG-Y2BOQKO-MNPHHQ4";
      host = "moby.tail5e510f.ts.net";
    };
    oppy = {
      id = "WUGSSP7-XBIOCPG-3JTGPIV-JSW4GFC-Z3U66BN-CZKTYC3-ADTX2IO-TG3DIQZ";
      host = "oppy.tail5e510f.ts.net";
    };
    spirit = {
      id = "2FPYDCN-NOTA4ZH-VCEORYQ-YL5NUUU-VCL3PXZ-DFMV7GR-DPN6PG5-Y7TPAAX";
      host = "spirit.tail5e510f.ts.net";
    };
    darwin001 = {
      id = "HQRQ26I-ZMMDORA-B6QCPZK-VDOCWAJ-JNXBONT-Z2TRSUL-V4U2PZT-ZHBFHQV";
      host = "alan-purdue-mbp.tail5e510f.ts.net";
    };
    darwin002 = {
      id = "OXQSPCP-XFPIUK7-QB646U3-YE5ZHIW-6WIPG36-G3PWKBE-FEIXCB6-ZUFAOAN";
      host = "wm9e9-3f5.tail5e510f.ts.net";
    };
  };
  # ix's older documents/session migration still references its historical
  # darwin002 identity. Do not alter those shares when enrolling backup peers.
  alias = name: if cfg.deviceName == "ix" && name == "darwin002" then "darwin002-backups" else name;
  remotePeers = lib.filterAttrs (name: _: name != cfg.deviceName) peers;
  devices = lib.mapAttrs' (name: peer: lib.nameValuePair (alias name) {
    id = lib.mkDefault peer.id;
    addresses = lib.mkDefault [ "tcp://${peer.host}:22000" ];
    autoAcceptFolders = lib.mkDefault false;
  }) remotePeers;
in
{
  options.ixBackupMesh = {
    enable = lib.mkEnableOption "encrypted ix measurement/state backup replication";
    deviceName = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum (builtins.attrNames peers));
      default = null;
      description = "Existing Syncthing identity of this host; never generates or replaces keys.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [ {
      assertion = cfg.deviceName != null;
      message = "ixBackupMesh needs the existing host's deviceName; never infer/reset its identity.";
    } ];
    services.syncthing = {
      enable = true;
      settings = {
        inherit devices;
        options = {
          natEnabled = false;
          # Resolve this host's tailnet name instead of listening on LAN/public
          # interfaces or hard-coding a Tailscale IP that may later change.
          listenAddresses = [ "tcp://${peers.${cfg.deviceName}.host}:22000" ];
        };
        folders.ix-backups = {
          id = "ix-backups";
          label = "ix encrypted backups";
          path = "${config.home.homeDirectory}/.local/share/syncthing/ix-backups";
          devices = map alias (builtins.attrNames remotePeers);
          type = if cfg.deviceName == "ix" then "sendonly" else "receiveonly";
          paused = false;
          ignorePerms = true;
          fsWatcherEnabled = true;
          # Prefer small hourly snapshots over the multi-GB legacy backlog.
          order = lib.mkIf (cfg.deviceName != "ix") "smallestFirst";
          # Unique, append-only archive names. Keep remotely deleted artifacts
          # indefinitely rather than treating synchronization as a backup alone.
          versioning = lib.mkIf (cfg.deviceName != "ix") {
            type = "trashcan";
            params.cleanoutDays = "0";
          };
        };
      };
    };
  };
}
