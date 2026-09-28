# Existing partitions: never format them during a rebuild/deployment.
{ ... }:
{
  fileSystems."/" = {
    device = "/dev/disk/by-partuuid/82f0384a-132d-483f-8888-98c201d166d7";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-partuuid/5e49d9dc-01";
    fsType = "vfat";
    # No routine application data lives here. Only boot updates write this SD.
    options = [
      "noatime"
      "umask=0077"
    ];
  };
  # The Raspberry Pi OS SD root and old HDD firmware partition are not mounted.
  swapDevices = [ ];
  boot.initrd.availableKernelModules = [
    "pcie_brcmstb"
    "xhci_pci"
    "usb_storage"
    "uas"
    "sd_mod"
    "ext4"
    "vfat"
  ];
  boot.kernelParams = [
    "console=tty0"
    "panic=30"
  ];
  # The one-shot test exposed Bluetooth UART failures. It is not needed for the
  # headless foundation; enable/test deliberately if an application needs it.
  boot.blacklistedKernelModules = [ "hci_uart" ];
  hardware.bluetooth.enable = false;
  hardware.enableRedistributableFirmware = true;
}
