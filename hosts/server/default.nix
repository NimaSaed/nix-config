{
  config,
  pkgs,
  ...
}:

{
  imports =
    [
#      ./disko.nix
      ./hardware-configuration.nix
      ../common/core
      ../common/users/nima
    ];

  # ZFS filesystem mounts (uncomment after creating the pool with disko)
  # fileSystems."/data" = {
  #   device = "datapool/data";
  #   fsType = "zfs";
  # };

  # Use the systemd-boot EFI boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable ZFS support
  boot.supportedFilesystems = [ "zfs" ];
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
  boot.zfs.forceImportRoot = false;
  # boot.zfs.extraPools = [ "datapool" ]; # Uncomment after creating pool with disko
  services.zfs.autoScrub.enable = true;

  # Enable networking
  networking.hostName = "server";
  networking.hostId = "8425e349"; # Required for ZFS (generate with: head -c 8 /etc/machine-id)
  networking.networkmanager.enable = true;

  # Enable zram swap for better memory management
  zramSwap.enable = true;
  zramSwap.memoryPercent = 50;

  # Set your time zone.
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

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
  };

  system.stateVersion = "25.05";
}
