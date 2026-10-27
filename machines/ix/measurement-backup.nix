{ config, pkgs, lib, ... }:
let
  output = "/home/amunoz/.local/share/syncthing/ix-backups/ix/measurements";
  recipients = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAKdcdlNS1SO+rJHjRQWd33qvqBEZcZR8ypTQUeC9LZ4"
    # Recovery private key is kept separately on Oppy, never in this mesh folder.
    "age1sagg4y0ax7ad4jk2gqaxx6cp0tf3hmsue5ghvrgnqpjc9j5hzufs8hqzaz"
  ];
in
{
  systemd.tmpfiles.rules = [
    "d ${output} 0700 amunoz ${config.users.users.amunoz.group} - -"
  ];
  systemd.services.ix-measurement-backup = {
    description = "Encrypted, consistent Home Assistant measurement snapshot";
    after = [ "home-assistant.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.escapeShellArgs ([
        "${pkgs.python3}/bin/python3"
        "${./measurement-backup.py}"
        "--source" "/var/lib/hass/home-assistant_v2.db"
        "--runtime" "/run/ix-measurement-backup"
        "--state" "/var/lib/ix-measurement-backup"
        "--output" output
        "--owner" "amunoz"
        "--age" "${pkgs.age}/bin/age"
        "--zstd" "${pkgs.zstd}/bin/zstd"
      ] ++ lib.concatMap (recipient: [ "--recipient" recipient ]) recipients);
      RuntimeDirectory = "ix-measurement-backup";
      RuntimeDirectoryMode = "0700";
      StateDirectory = "ix-measurement-backup";
      StateDirectoryMode = "0700";
      UMask = "0077";
      TimeoutStartSec = "3min";
      Nice = 19;
      IOSchedulingClass = "idle";
      MemoryMax = "768M";
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateNetwork = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadOnlyPaths = [ "/var/lib/hass" ];
      ReadWritePaths = [ output ];
    };
  };
  systemd.timers.ix-measurement-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      RandomizedDelaySec = "2min";
      Persistent = true;
    };
  };
}
