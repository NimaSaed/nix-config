# Btrfs RAID1 on NVMe mirror
# Two NVMe drives with separate ESPs and btrfs RAID1 for root
#
# Layout per drive:
#   Part 1: ESP (1G) - EFI System Partition
#   Part 2: btrfs RAID1 (rest) - data & metadata mirrored
#
# ESP Strategy:
#   - nvme0 ESP mounted at /boot (primary)
#   - nvme1 ESP mounted at /boot-backup (synced via systemd)
#   - If primary fails, UEFI can boot from backup
#
# RAID1 Strategy:
#   Disko processes disks alphabetically. nvme0 defines a raw partition
#   (no content), then nvme1's btrfs content block references nvme0's
#   partition via extraArgs to create the RAID1 array across both drives.
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
            # Primary EFI System Partition - mounted at /boot
            esp = {
              size = "1G";
              type = "EF00";
              priority = 1;
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" "nofail" ];
              };
            };
            # Btrfs RAID1 member (raw partition, no content here)
            btrfs = {
              size = "100%";
              priority = 2;
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
            # Backup EFI System Partition - mounted at /boot-backup
            esp = {
              size = "1G";
              type = "EF00";
              priority = 1;
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot-backup";
                mountOptions = [ "umask=0077" "nofail" ];
              };
            };
            # Btrfs RAID1 - creates the array across both drives
            btrfs = {
              size = "100%";
              priority = 2;
              content = {
                type = "btrfs";
                extraArgs = [
                  "-f"
                  "-d raid1"
                  "-m raid1"
                  "/dev/disk/by-partlabel/disk-nvme0-btrfs"
                ];
                subvolumes = {
                  "@root" = {
                    mountpoint = "/";
                    mountOptions = [ "compress=zstd" "ssd" ];
                  };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = [ "compress=zstd" "noatime" "ssd" ];
                  };
                  "@var" = {
                    mountpoint = "/var";
                    mountOptions = [ "compress=zstd" "ssd" ];
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = [ "compress=zstd" "ssd" ];
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
