# Disko configuration for hazelnut (LattePanda iota)
# Single eMMC: mmc-DUTB42_0xa87453d3 (128GB eMMC 5.1)
# ext4 root with eMMC-optimized mount options, systemd-boot ESP
{
  disko.devices = {
    disk = {
      root = {
        device = "/dev/disk/by-id/mmc-DUTB42_0xa87453d3";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              priority = 1;
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              size = "100%";
              priority = 2;
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = [
                  "noatime" # Reduce write amplification on eMMC
                  "discard" # Inline TRIM for eMMC wear leveling
                ];
              };
            };
          };
        };
      };
    };
  };
}
