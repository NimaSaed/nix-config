{
  disko.devices = {
    disk = {
      sda = {
        type = "disk";
        device = "/dev/disk/by-id/wwn-0x5000c500e9dbd8c6";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "datapool";
              };
            };
          };
        };
      };
      sdb = {
        type = "disk";
        device = "/dev/disk/by-id/wwn-0x5000c500e9e021d0";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "datapool";
              };
            };
          };
        };
      };
    };
    zpool = {
      datapool = {
        type = "zpool";
        mode = "mirror";
        rootFsOptions = {
          compression = "zstd";
          atime = "off";
          mountpoint = "/data";
        };
      };
    };
  };
}
