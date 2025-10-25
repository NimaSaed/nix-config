{
  disko.devices = {
    disk.data = {
      type = "disk";
      device = "/dev/sdb";
      content = {
        type = "gpt";
        partitions.data = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/data";
          };
        };
      };
    };
    disk.data1 = {
      type = "disk";
      device = "/dev/sdc";
      content = {
        type = "gpt";
        partitions.data = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/data";
          };
        };
      };
    };
  };
}
