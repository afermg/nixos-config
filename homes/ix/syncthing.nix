# Preserve the existing tailnet-only policy. Enrollment and remote acceptance
# must be verified before unpausing; a seeded copy is not live synchronization.
{ config, ... }:
let
  peers = [
    "moby"
    "darwin001"
    "darwin002"
  ];
in
{
  services.syncthing = {
    enable = true;
    guiAddress = "127.0.0.1:8384";
    overrideDevices = true;
    overrideFolders = true;
    settings = {
      options = {
        globalAnnounceEnabled = false;
        localAnnounceEnabled = false;
        relaysEnabled = false;
        listenAddresses = [ "tcp://0.0.0.0:22000" ];
        urAccepted = -1;
      };
      devices = {
        moby = {
          id = "IBGBMDU-WRH5ECV-YS3BFJ7-EPJPC5X-HVLGWGA-RUIFYSG-Y2BOQKO-MNPHHQ4";
          addresses = [ "tcp://moby.tail5e510f.ts.net:22000" ];
        };
        darwin001 = {
          id = "HQRQ26I-ZMMDORA-B6QCPZK-VDOCWAJ-JNXBONT-Z2TRSUL-V4U2PZT-ZHBFHQV";
          addresses = [ "tcp://alan-purdue-mbp.tail5e510f.ts.net:22000" ];
        };
        darwin002 = {
          id = "TKXRRWK-K5EDNVM-AVXZKCP-TE2M2LC-A7CYJB7-LY2G5MU-EYGHIZC-I6GMRAR";
          addresses = [ "tcp://sce-bio-c06399.tail5e510f.ts.net:22000" ];
        };
      };
      folders = {
        documents = {
          id = "documents";
          label = "Documents working copy";
          path = "${config.home.homeDirectory}/Documents";
          devices = peers;
          paused = true;
          type = "receiveonly"; # Change deliberately after all peers reconcile.
          ignorePerms = true;
          ignorePatterns = [
            ".rsync-partial"
            ".ssh"
            ".gnupg"
            ".env"
            ".env.*"
          ];
        };
        pi-sessions = {
          id = "pi-sessions";
          label = "Pi session working copy";
          path = "${config.home.homeDirectory}/.pi/agent/sessions";
          devices = peers;
          paused = true;
          type = "receiveonly";
          ignorePerms = true;
          ignorePatterns = [ ".rsync-partial" ];
        };
      };
    };
  };
}
