# Disko configuration for chestnut
# Two disks: sda (root) and sdb (data), both XFS with GRUB BIOS boot
{
  disko.devices = {
    disk = {
      # Root disk - /dev/sda
      root = {
        device = "/dev/sda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            # BIOS boot partition for GRUB (required for GPT + BIOS)
            # This partition is used by GRUB to store its core.img
            boot = {
              size = "1M";
              type = "EF02";
              priority = 1;
            };
            # Root filesystem
            root = {
              size = "100%";
              priority = 2;
              content = {
                type = "filesystem";
                format = "xfs";
                mountpoint = "/";
              };
            };
          };
        };
      };

      # Data disk - /dev/sdb
      data = {
        device = "/dev/sdb";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "xfs";
                mountpoint = "/data";
              };
            };
          };
        };
      };
    };
  };
}
