{ lib, ... }:
{
  disko.devices = {
    disk = {
      nvme0 = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1G";
              type = "EF00"; # EFI System Partition
              content = {
                type = "mdraid";
                name = "boot";
              };
            };
            root = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "root";
              };
            };
          };
        };
      };
      nvme1 = {
        type = "disk";
        device = "/dev/nvme1n1";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1G";
              type = "EF00"; # EFI System Partition
              content = {
                type = "mdraid";
                name = "boot";
              };
            };
            root = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "root";
              };
            };
          };
        };
      };
    };

    mdadm = {
      boot = {
        type = "mdadm";
        level = 1;
        metadata = "1.0"; # Metadata at END of partition for UEFI compatibility
        content = {
          type = "filesystem";
          format = "vfat";
          mountpoint = "/boot";
          mountOptions = [
            "fmask=0022"
            "dmask=0022"
            "noatime"
          ];
        };
      };
      root = {
        type = "mdadm";
        level = 1;
        metadata = "1.2"; # Standard metadata for data partitions
        content = {
          type = "filesystem";
          format = "xfs";
          mountpoint = "/";
          mountOptions = [
            "noatime"
            "nodiratime"
            "discard"
            "inode64"
          ];
        };
      };
    };
  };
}
