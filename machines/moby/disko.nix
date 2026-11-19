{
  disko.memSize = 16384; # 16GB
  disko.devices = {
    disk = {
      # Retained SSD with the EFI partition. Never depend on NVMe enumeration.
      ssd0 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-eui.002538414144b5fb";
        imageSize = "10G"; # For VM
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };
      # Former ssd1 (EUI ...b5f9, serial S7KGNJ0X158409E) was evacuated
      # with ZFS top-level device removal. Do not recreate it on rebuild.

      # HDD cluster
      hdd0 = {
        type = "disk";
        device = "/dev/disk/by-id/wwn-0x5000c500e84abb69";
        imageSize = "10G";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zstore";
              };
            };
          };
        };
      };

      hdd1 = {
        type = "disk";
        device = "/dev/disk/by-id/wwn-0x5000c500e86adcbe";
        imageSize = "10G";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zstore";
              };
            };
          };
        };
      };
    };
    # Z pool definitions
    zpool = {
      zroot = {
        type = "zpool";
        mode = "";
        rootFsOptions = {
          # Make sure these options are correct
          # canmount = "off";
          acltype = "posixacl";
          dnodesize = "auto";
          normalization = "formD";
          atime = "off";
          compression = "lz4";
          mountpoint = "none";
          xattr = "sa";
          "com.sun:auto-snapshot" = "false";
        };
        options.ashift = "12";
        options.autotrim = "on";

        datasets = {
          "local" = {
            type = "zfs_fs";
            options.mountpoint = "none";
          };
          # "local/home" = {
          #   type = "zfs_fs";
          #   mountpoint = "/home";
          #   options."com.sun:auto-snapshot" = "true";
          # };
          "local/nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options."com.sun:auto-snapshot" = "false";
          };
          "local/root" = {
            type = "zfs_fs";
            mountpoint = "/";
            options."com.sun:auto-snapshot" = "false";
            postCreateHook = "zfs snapshot zroot/local/root@blank";
          };
        };
      };

      zstore = {
        type = "zpool";
        mode = "";
        rootFsOptions = {
          # Make sure these options are correct
          acltype = "posixacl";
          dnodesize = "auto";
          normalization = "formD";
          atime = "off";
          compression = "lz4";
          mountpoint = "none";
          xattr = "sa";
          "com.sun:auto-snapshot" = "false";
        };
        options.ashift = "12";
        options.autotrim = "on";

        datasets = {
          datastore = {
            type = "zfs_fs";
            options."com.sun:auto-snapshot" = "false";
            options.mountpoint = "/datastore";
            # /datastore currently contains unrelated SSD-root data. Mount
            # this legacy HDD dataset only explicitly, at a reviewed path.
            options.canmount = "noauto";
            postCreateHook = "zfs snapshot zstore/datastore@blank";
          };
        };
      };
    };
  };
}
