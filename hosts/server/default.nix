{
  config,
  pkgs,
  ...
}:

{
  imports =
    [
      ./hardware-configuration.nix
      ./disko-config.nix
      ../common/users/nima
    ];

  # Use the systemd-boot EFI boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable software RAID support
  boot.swraid.enable = true;
  boot.swraid.mdadmConf = ''
    MAILADDR root
    # Boot partition RAID1 (metadata 1.0 for UEFI compatibility)
    ARRAY /dev/md/boot level=raid1 num-devices=2 metadata=1.0
    # Root partition RAID1
    ARRAY /dev/md/root level=raid1 num-devices=2 metadata=1.2
  '';

  # Enable networking
  networking.hostName = "server";
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
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  system.stateVersion = "25.05";
}
