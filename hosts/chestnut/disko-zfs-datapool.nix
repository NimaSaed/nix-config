# ZFS data pool on SATA HDDs - Seagate IronWolf Pro 22TB
# Optimized for Samba file sharing with proper sector alignment
#
# CRITICAL settings for this hardware:
#   - ashift=12: Required for 4K physical sector IronWolf drives
#   - xattr=sa: Required for Samba extended attributes performance
#   - acltype=posixacl: Required for Samba/Windows ACL translation
{
  disko.devices = {
    disk = {
      # ========================================================================
      # SATA Drive 0 - First mirror member
      # ========================================================================
      sata0 = {
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

      # ========================================================================
      # SATA Drive 1 - Second mirror member
      # ========================================================================
      sata1 = {
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

    # ==========================================================================
    # ZFS Data Pool Configuration
    # ==========================================================================
    zpool = {
      datapool = {
        type = "zpool";
        mode = "mirror";

        # Pool-level options (set at creation time with -o)
        # CRITICAL: ashift=12 for 4K physical sector IronWolf Pro drives
        options = {
          ashift = "12";
          cachefile = "none";
        };

        # Root dataset options (inherited by children)
        # CRITICAL: xattr=sa and acltype=posixacl for Samba
        rootFsOptions = {
          canmount = "off";
          compression = "zstd";
          atime = "off";
          xattr = "sa";
          acltype = "posixacl";
          dnodesize = "auto";
          recordsize = "1M"; # Good default for large media files
          mountpoint = "none"; # Don't mount pool root
          "com.sun:auto-snapshot" = "true";
        };

        # =======================================================================
        # Dataset Hierarchy for /data
        # =======================================================================
        datasets = {
          # Main data dataset - mounted at /data
          "data" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/data";
          };

          # Media - large sequential files (video, music)
          "data/media" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/data/media";
            options.recordsize = "1M";
          };

          # Backups - higher compression ratio
          "data/backups" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/data/backups";
            options.compression = "zstd-9";
          };

          # Containers - for podman volumes
          "data/containers" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/data/containers";
            options.recordsize = "128K";
          };
        };
      };
    };
  };
}
