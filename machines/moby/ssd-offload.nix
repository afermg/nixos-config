{ pkgs, ... }:
let
  runtime = "${pkgs.bash}/bin/bash ${./ssd-offload-runtime.sh}";
  importUnit = "moby-ssd-offload-import.service";
in
{
  # Explicitly import only the intended HDD pool, with no dataset automounts.
  # No zpool clear, forced import, pool upgrade, or boot-time device removal.
  systemd.services.moby-sata-performance = {
    description = "Disable SATA link power saving on Moby's two offload HDDs";
    unitConfig.DefaultDependencies = false;
    wants = [ "systemd-udev-settle.service" ];
    after = [ "systemd-udev-settle.service" ];
    before = [ importUnit ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${runtime} sata-performance";
      TimeoutStartSec = 90;
    };
  };

  systemd.services.moby-ssd-offload-import = {
    description = "Import Moby HDD offload pool without mounting unrelated datasets";
    unitConfig.DefaultDependencies = false;
    requires = [ "moby-sata-performance.service" ];
    after = [
      "moby-sata-performance.service"
      "zfs-import.target"
    ];
    before = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${runtime} import";
      TimeoutStartSec = 120;
    };
  };

  # A wanted (not required) local mount: an unavailable HDD must not prevent
  # booting the SSD root. Selected home paths then fail rather than silently
  # creating replacement data on the SSD (underlying mount directory is 000).
  systemd.mounts = [
    {
      description = "Moby bulk home data on HDDs";
      what = "zstore/ssd-migration/bulk";
      where = "/srv/ssd-offload";
      type = "zfs";
      options = "zfsutil";
      requires = [ importUnit ];
      after = [ importUnit ];
      before = [ "local-fs.target" ];
      wantedBy = [ "local-fs.target" ];
      mountConfig.TimeoutSec = 120;
    }
  ];
}
