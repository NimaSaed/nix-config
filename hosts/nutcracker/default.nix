{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ./data-mount.nix
    ../common/core
    ../common/users/nima
  ];

  # ============================================================================
  # Podman Pods - Enable container services for this host
  # ============================================================================
  # Pod modules are defined in modules/podman/ with enable options
  services.pods = {
    reverse-proxy = {
      enable = true;
      useAcmeStaging = true;
    };
    tools = {
      enable = true;
      homepage.enable = true;
      itTools.enable = false;
    };
    media = {
      enable = true;
      jellyfin.enable = true;
    };
    #auth = {
    #  enable = true;
    #  authelia.enable = true;
    #  lldap.enable = true;
    #};
  };

  # ============================================================================
  # Boot Configuration
  # ============================================================================

  # Use GRUB bootloader with BIOS support
  boot.loader.grub = {
    enable = true;
  };

  # Enable zram swap for better memory management
  zramSwap.enable = true;
  zramSwap.memoryPercent = 50;

  # ============================================================================
  # Networking
  # ============================================================================
  # Nutcracker - cracks open the nuts (processes data from chestnut)
  networking.hostName = "nutcracker";
  networking.networkmanager.enable = true;

  # Enable systemd-resolved for reliable DNS at boot
  # Required for CIFS mount to resolve chestnut.nmsd.xyz before mounting /data
  services.resolved.enable = true;
  networking.networkmanager.dns = "systemd-resolved";

  # Enable network-online.target at boot for podman user containers
  # Without this, podman-user-wait-network-online.service times out (90s)
  # during nixos-rebuild switch, causing slow sysinit-reactivation.target
  # See: https://github.com/containers/podman/issues/24796
  systemd.targets.network-online.wantedBy = [ "multi-user.target" ];

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
  services.openssh = {
    enable = true;
  };

  # ============================================================================
  # User Configuration
  # ============================================================================

  # Configure root user for emergency mode access
  users.users.root = {
    # Set root password (same as nima's) for emergency mode access
    initialHashedPassword = "$y$j9T$VIgEJ4u79wZRwEny9XepM1$1sYHPUO7bIl5PQtSYE.Ptra8zIFBQyh1AlxKmfAkFg/";
    # Allow root SSH access with public key
    openssh.authorizedKeys.keys = lib.splitString "\n" (builtins.readFile ../../home/nima/ssh.pub);
  };

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
    validateSopsFiles = false;

    # Use dedicated age key for decryption
    age.keyFile = "/var/lib/sops-nix/key.txt";
  };

  system.stateVersion = "25.11";
}
