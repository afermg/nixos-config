# A bootspec-driven, direct-firmware boot backend. No U-Boot USB dependency.
{ config, pkgs, ... }:
let
  tools = pkgs.runCommand "ix-boot-tools" { } ''
    mkdir -p "$out"
    cp ${./bootloader.py} "$out/bootloader.py"
    cp ${./recovery.py} "$out/recovery.py"
  '';
  policy = pkgs.writeText "ix-boot-policy.json" (
    builtins.toJSON {
      mountPoint = "/boot";
      bootDevice = config.fileSystems."/boot".device;
      rootDevice = config.fileSystems."/".device;
      recoveryRootDevice = "/dev/disk/by-partuuid/5e49d9dc-02";
      helperDirectory = "${tools}";
      ethernetMac = "dc:a6:32:c2:0b:8b";
      hddDevice = "/dev/disk/by-id/usb-WD_My_Passport_25E2_575834314441385046444858-0:0";
      hddSerial = "WD-WX41DA8PFDHX";
      hddBytes = 4000752599040;
      retain = 2;
      recoveryHashes = {
        "config.txt" = "90a446821551a9df109ec1a77a79f6518fe974517d982d371c5e9efd6bbc98c3";
        "cmdline.txt" = "671c75ae0c695219317ef297cb19a524c61252d7741df55dabcf3100078f8caa";
      };
    }
  );
  installer = pkgs.writeShellApplication {
    name = "ix-install-boot";
    runtimeInputs = [
      pkgs.python3
      pkgs.util-linux
    ];
    text = ''
      if [ "$#" -ne 1 ]; then
        echo "usage: ix-install-boot /nix/store/...-nixos-system-ix-..." >&2
        exit 2
      fi
      exec python3 ${tools}/bootloader.py install --policy ${policy} --system "$1"
    '';
  };
  recovery = pkgs.writeShellApplication {
    name = "ix-recovery";
    runtimeInputs = [
      pkgs.python3
      pkgs.util-linux
      pkgs.systemd
    ];
    text = ''
      exec python3 ${tools}/recovery.py select --policy ${policy} --reboot "$@"
    '';
  };
  bootTree = pkgs.runCommand "ix-boot-tree" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 ${tools}/bootloader.py build-tree \
      --system ${config.system.build.toplevel} --output "$out"
  '';
in
{
  boot.loader = {
    grub.enable = false;
    generic-extlinux-compatible.enable = false;
    external = {
      enable = true;
      installHook = "${installer}/bin/ix-install-boot";
    };
  };
  # Stable on-disk protocol identifier: retain compatibility with proven rollback tools.
  boot.bootspec.extensions."org.afermg.raspi4.v1" = {
    dtb = "${config.boot.kernelPackages.kernel}/dtbs/broadcom/bcm2711-rpi-4-b.dtb";
    armstub = "${pkgs.raspberrypi-armstubs}/armstub8-gic.bin";
    firmware = "${pkgs.raspberrypifw}/share/raspberrypi/boot";
  };
  environment.systemPackages = [
    installer
    recovery
  ];
  system.build.ixBootTree = bootTree;
  # Build before deployment. This FAT filesystem image is a boot artifact,
  # not a whole-disk installer: never dd it over the existing SD or HDD.
  system.build.ixBootImage =
    pkgs.runCommand "ix-boot-image"
      {
        nativeBuildInputs = [
          pkgs.dosfstools
          pkgs.mtools
        ];
      }
      ''
        mkdir -p "$out"
        truncate -s 256M "$out/ix-boot.fat.img"
        mkfs.vfat --invariant -F 32 -i 52504934 -n RPI4_NIX "$out/ix-boot.fat.img"
        mcopy -s -i "$out/ix-boot.fat.img" ${bootTree}/* ::/
        fsck.fat -n "$out/ix-boot.fat.img"
        cp ${bootTree}/manifest.json "$out/manifest.json"
        sha256sum "$out/ix-boot.fat.img" > "$out/SHA256SUMS"
      '';
}
