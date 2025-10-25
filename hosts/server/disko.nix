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
            ESP = {
              priority = 1;
              size = "1G";
              type = "EF00"; # EFI System Partition
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "fmask=0077"
                  "dmask=0077"
                  "noatime"
                ];
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
            ESP = {
              priority = 1;
              size = "1G";
              type = "EF00"; # EFI System Partition - mirror of nvme0 ESP
              content = {
                type = "filesystem";
                format = "vfat";
                # Not mounted - this is a backup ESP
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
