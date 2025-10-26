{ config, lib, pkgs, ... }:

{
  imports = [
    ./disko-nvme-boot-raid1.nix
    ./disko-zfs-datapool.nix
    ./hardware-configuration.nix
    ../common/core
    ../common/users/nima
  ];

  # ============================================================================
  # Boot Configuration
  # ============================================================================

  # Use GRUB bootloader with RAID support
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    mirroredBoots = [{
      devices = [ "nodev" ];
      path = "/boot";
    }];
  };

  # Enable ZFS support
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  # Note: ZFS pools and scrubbing can be configured here if needed
  boot.zfs.extraPools = [ "datapool" ];
  # services.zfs.autoScrub.enable = true;

  # Enable zram swap for better memory management
  zramSwap.enable = true;
  zramSwap.memoryPercent = 50;

  # ============================================================================
  # Networking
  # ============================================================================
  # Chestnut - a safe place for your "nuts" (data)
  networking.hostName = "chestnut";
  networking.hostId =
    "8425e349"; # Required for ZFS (generate with: head -c 8 /etc/machine-id)
  networking.networkmanager.enable = true;

  # ============================================================================
  # Localization
  # ============================================================================

  # Set your time zone
  time.timeZone = "Europe/Amsterdam";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "nl_NL.UTF-8";
    LC_IDENTIFICATION = "nl_NL.UTF-8";
    LC_MEASUREMENT = "nl_NL.UTF-8";
    LC_MONETARY = "nl_NL.UTF-8";
    LC_NAME = "nl_NL.UTF-8";
    LC_NUMERIC = "nl_NL.UTF-8";
    LC_PAPER = "nl_NL.UTF-8";
    LC_TELEPHONE = "nl_NL.UTF-8";
    LC_TIME = "nl_NL.UTF-8";
  };

  # ============================================================================
  # Services
  # ============================================================================

  # Enable the OpenSSH daemon
  services.openssh = { enable = true; };

  services.cockpit = {
    enable = true;
    openFirewall = true;
    allowed-origins = [ "https://chestnut:9090" "https://chestnut.nmsd.xyz:9090" ];
  };

  services.udisks2.enable = true;

  # ============================================================================
  # User Configuration
  # ============================================================================

  # Configure root user for emergency mode access
  users.users.root = {
    # Set root password (same as nima's) for emergency mode access
    initialHashedPassword =
      "$y$j9T$VIgEJ4u79wZRwEny9XepM1$1sYHPUO7bIl5PQtSYE.Ptra8zIFBQyh1AlxKmfAkFg/";
    # Allow root SSH access with public key
    openssh.authorizedKeys.keys =
      lib.splitString "\n" (builtins.readFile ../../home/nima/ssh.pub);
  };

  # Grant nima access to /data directory
  systemd.tmpfiles.rules = [ "d /data 0755 nima users - -" ];

  system.stateVersion = "25.05";
}
