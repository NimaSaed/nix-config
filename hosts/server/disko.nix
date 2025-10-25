{
  disko.devices = {
    disk.data0 = {
      type = "disk";
      device = "/dev/sda";
      content = {
        type = "gpt";
        partitions.data = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/data0";
          };
        };
      };
    };
    disk.data1 = {
      type = "disk";
      device = "/dev/sdb";
      content = {
        type = "gpt";
        partitions.data = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/data1";
          };
        };
      };
    };
  };
}
