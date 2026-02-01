# ZFS root pool on NVMe mirror - Proxmox-style configuration
# Two NVMe drives with separate ESPs and ZFS mirror for root
#
# Layout per drive:
#   Part 1: BIOS boot (1M) - for GRUB legacy fallback
#   Part 2: ESP (1G) - EFI System Partition
#   Part 3: ZFS (rest) - rpool mirror member
#
# ESP Strategy:
#   - nvme0 ESP mounted at /boot (primary)
#   - nvme1 ESP mounted at /boot-backup (synced via systemd)
#   - If primary fails, UEFI can boot from backup
{ lib, ... }:
{
  disko.devices = {
    disk = {
      # ========================================================================
      # NVMe Drive 0 - Primary boot drive
      # ========================================================================
      nvme0 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-eui.0025388981be9a45";
        content = {
          type = "gpt";
          partitions = {
            # BIOS boot partition for GRUB (required for GPT + BIOS legacy)
            bios = {
              size = "1M";
              type = "EF02";
              priority = 1;
            };
            # Primary EFI System Partition - mounted at /boot
            esp = {
              size = "1G";
              type = "EF00";
              priority = 2;
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" "nofail" ];
              };
            };
            # ZFS partition for rpool mirror
            zfs = {
              size = "100%";
              priority = 3;
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };

      # ========================================================================
      # NVMe Drive 1 - Secondary/backup boot drive
      # ========================================================================
      nvme1 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-eui.0025388981be99d3";
        content = {
          type = "gpt";
          partitions = {
            # BIOS boot partition for GRUB
            bios = {
              size = "1M";
              type = "EF02";
              priority = 1;
            };
            # Backup EFI System Partition - mounted at /boot-backup
            esp = {
              size = "1G";
              type = "EF00";
              priority = 2;
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot-backup";
                mountOptions = [ "umask=0077" "nofail" ];
              };
            };
            # ZFS partition for rpool mirror
            zfs = {
              size = "100%";
              priority = 3;
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };
    };

    # ==========================================================================
    # ZFS Root Pool Configuration
    # ==========================================================================
    zpool = {
      rpool = {
        type = "zpool";
        mode = "mirror";

        # Pool-level options (set at creation time with -o)
        options = {
          ashift = "12"; # 4K sectors (safe for all modern NVMe)
          cachefile = "none"; # NixOS manages pool imports
        };

        # Root dataset options (inherited by children)
        # Based on NixOS wiki recommendations
        rootFsOptions = {
          canmount = "off";
          compression = "zstd";
          mountpoint = "none";
          xattr = "sa";
          acltype = "posixacl";
          atime = "off";
          "com.sun:auto-snapshot" = "false";
        };

        # =======================================================================
        # Dataset Hierarchy
        # =======================================================================
        datasets = {
          # Root filesystem - mounted at /
          "root/nixos" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/";
          };

          # Nix store
          "root/nix" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/nix";
          };

          # /var - logs, state, containers
          "root/var" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/var";
            options."com.sun:auto-snapshot" = "true";
          };

          # Home directories
          "root/home" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/home";
            options."com.sun:auto-snapshot" = "true";
          };
        };
      };
    };
  };
}
