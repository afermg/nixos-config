{
  lib,
  pkgs,
  ...
}:
let
  backupRoot = "/home/amunoz/.local/share/syncthing/ix-backups/ix";
  stagingRoot = "/var/lib/ix-state-backup";
  personalAgeRecipient = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAKdcdlNS1SO+rJHjRQWd33qvqBEZcZR8ypTQUeC9LZ4";
  ixHostAgeRecipient = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKY0holJSH6l/MeBPRWgzITfAVwT7dJESRBTP0pHjQA7";
  backupNow = pkgs.writeShellApplication {
    name = "ix-state-backup-now";
    runtimeInputs = with pkgs; [ systemd ];
    text = ''
      set -euo pipefail
      exec /run/wrappers/bin/sudo systemctl start ix-state-backup.service
    '';
  };
in
{
  environment.systemPackages = [ backupNow ];

  systemd.tmpfiles.rules = [
    "d ${stagingRoot} 0700 root root -"
    "d /home/amunoz/.local/share/syncthing/ix-backups 0700 amunoz users -"
    "d ${backupRoot} 0700 amunoz users -"
  ];

  systemd.services.ix-state-backup = {
    description = "Create an encrypted backup of ix-owned state";
    path = with pkgs; [
      age
      coreutils
      findutils
      gnutar
      zstd
    ];
    script = ''
      set -euo pipefail
      umask 077
      stamp=$(date -u +%Y%m%dT%H%M%SZ)
      plain=${lib.escapeShellArg stagingRoot}/ix-state-$stamp.tar.zst
      encrypted=${lib.escapeShellArg backupRoot}/ix-state-$stamp.tar.zst.age
      temporary=$encrypted.tmp
      checksum_tmp=$encrypted.sha256.tmp
      manifest=${lib.escapeShellArg stagingRoot}/ix-state-$stamp.manifest
      cleanup() {
        rm -f "$plain" "$temporary" "$checksum_tmp" "$manifest"
      }
      trap cleanup EXIT

      : > "$manifest"
      add_source() {
        local path=$1
        if [ -e "/$path" ]; then
          printf '%s\n' "$path" >> "$manifest"
        else
          echo "Skipping missing backup source: /$path" >&2
        fi
      }

      add_source home/amunoz/.pi/agent/sessions
      add_source home/amunoz/.pi/agent/missions
      add_source home/amunoz/.pi/agent/run-history.jsonl
      add_source home/amunoz/.pi/agent/dashboard-manifest.el
      add_source home/amunoz/.elfeed
      add_source home/amunoz/.config/hindsight/api-token
      add_source home/amunoz/.local/state/syncthing/config.xml
      add_source home/amunoz/.local/state/syncthing/cert.pem
      add_source home/amunoz/.local/state/syncthing/key.pem
      add_source home/amunoz/.local/share/syncthing/private-docs-01
      add_source home/amunoz/.local/share/syncthing/hindsight-backups
      add_source home/amunoz/Documents/broad/org

      tar \
        --create \
        --zstd \
        --file "$plain" \
        --directory / \
        --files-from "$manifest" \
        --warning=no-file-changed \
        --ignore-failed-read

      age \
        -r ${lib.escapeShellArg personalAgeRecipient} \
        -r ${lib.escapeShellArg ixHostAgeRecipient} \
        -o "$temporary" \
        "$plain"
      age -d -i /etc/ssh/ssh_host_ed25519_key "$temporary" \
        | tar --zstd --list --file - >/dev/null
      chown amunoz:users "$temporary"
      chmod 0600 "$temporary"
      mv "$temporary" "$encrypted"
      (
        cd "$(dirname "$encrypted")"
        sha256sum "$(basename "$encrypted")" > "$checksum_tmp"
      )
      chown amunoz:users "$checksum_tmp"
      chmod 0600 "$checksum_tmp"
      mv "$checksum_tmp" "$encrypted.sha256"

      find ${lib.escapeShellArg backupRoot} -maxdepth 1 -type f \
        -name 'ix-state-*.tar.zst.age' -mtime +90 -delete
      find ${lib.escapeShellArg backupRoot} -maxdepth 1 -type f \
        -name 'ix-state-*.tar.zst.age.sha256' -mtime +90 -delete
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };

  systemd.timers.ix-state-backup = {
    description = "Weekly encrypted ix state backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sat *-*-* 03:40:00";
      Persistent = true;
      RandomizedDelaySec = "45m";
      Unit = "ix-state-backup.service";
    };
  };
}
