{ ... }:
{
  # Import only the intended HDD pool and mount only its offloaded-home dataset.
  # Never force-import every discoverable pool or cover the SSD /datastore path.
  imports = [ ./ssd-offload.nix ];

  boot.kernelParams = [ "nohibernate" ];
  boot.zfs.forceImportRoot = false;
  boot.loader.grub = {
    enable = true;
    zfsSupport = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    # Keep GRUB independent of ZFS indirect vdev mappings after SSD removal.
    copyKernels = true;
    mirroredBoots = [
      {
        devices = [ "nodev" ];
        path = "/boot";
      }
    ];
  };
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;
  services.nfs.server.enable = true;
}
