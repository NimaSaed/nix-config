{ config, lib, pkgs, ... }:

{
  imports = [
    #./disko-nvme-boot-raid1.nix
    #./disko-zfs-datapool.nix
    ./hardware-configuration.nix
    ../common/core
    ../common/users/nima
    ../common/users/poddy
    ../common/podman/podman.nix
    ../common/podman/container-traefik.nix
  ];

  # ============================================================================
  # Boot Configuration
  # ============================================================================

  # Use GRUB bootloader with RAID support
  boot.loader.grub = {
    enable = true;
    #efiSupport = true;
    #efiInstallAsRemovable = true;
    #mirroredBoots = [{
    #  devices = [ "nodev" ];
    #  path = "/boot";
    #}];
    device = "/dev/sda";
  };

  # Enable ZFS support
  #boot.supportedFilesystems = [ "zfs" ];
  #boot.zfs.forceImportRoot = false;
  # Note: ZFS pools and scrubbing can be configured here if needed
  #boot.zfs.extraPools = [ "datapool" ];
  # services.zfs.autoScrub.enable = true;

  # Enable zram swap for better memory management
  zramSwap.enable = true;
  zramSwap.memoryPercent = 50;

  # ============================================================================
  # Networking
  # ============================================================================
  # Chestnut - a safe place for your "nuts" (data)
  networking.hostName = "chestnut";
  #networking.hostId =
  #  "6b2b4dde"; # Required for ZFS (generate with: head -c 8 /etc/machine-id)
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

  # Create /data directory structure
  # /data must be owned by root to allow subdirectories with different owners
  systemd.tmpfiles.rules = [
    "d /data 0755 root root - -"
    # Nima's personal data directory
    "d /data/nima 0755 nima users - -"
    # Traefik storage directory on ZFS datapool
    "d /data/traefik 0755 poddy poddy - -"
    "f /data/traefik/acme.json 0600 poddy poddy - -"
  ];

  # ============================================================================
  # Secrets Management - sops-nix
  # ============================================================================
  # Secrets are encrypted with age and stored in secrets.yaml
  # Generate age key: ssh-keyscan localhost | ssh-to-age
  # Or use existing SSH host key: /etc/ssh/ssh_host_ed25519_key

  sops = {
    # Default secrets file for this host
    defaultSopsFile = ./secrets.yaml;

    # Validate sops file exists at evaluation time
    validateSopsFiles = true;  # Set to true after creating secrets.yaml

    # Use SSH host key for decryption (no separate age key needed)
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # Define secrets that will be available to services
    secrets = {
      namecheap_email = {
        owner = "poddy";
        group = "poddy";
      };
      namecheap_api_user = {
        owner = "poddy";
        group = "poddy";
      };
      namecheap_api_key = {
        owner = "poddy";
        group = "poddy";
      };
    };
  };

  system.stateVersion = "25.05";
}
