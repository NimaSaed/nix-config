# Minimal NixOS Installer ISO Configuration
# This creates a bootable ISO with SSH access for remote deployment
{ config, pkgs, lib, modulesPath, ... }:

{
  # Import the minimal installation ISO base configuration
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # =========================================================================
  # SSH Configuration - Enable remote access
  # =========================================================================
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true; # Allow password as fallback
    };
  };

  # Add SSH public key for root user
  users.users.root = {
    # Set a default password for emergency console access
    # Password: "installer"
    initialPassword = "installer";

    openssh.authorizedKeys.keys = [
      # Your SSH public key from home/nima/ssh.pub
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILusNnhBC/pBjhZpx312e7TEzwS69SyN/0e/osA6Jez9"
    ];
  };

  # =========================================================================
  # Networking - Enable DHCP and WiFi support
  # =========================================================================
  networking = {
    # Use DHCP on all interfaces
    useDHCP = lib.mkDefault true;

    # Enable wireless support (for WiFi)
    wireless.enable = true;
    wireless.userControlled.enable = true;
  };

  # =========================================================================
  # System Packages - Minimal tools for installation
  # =========================================================================
  environment.systemPackages = with pkgs; [
    git    # For cloning configurations
    vim    # Text editor
  ];

  # =========================================================================
  # ISO Image Configuration
  # =========================================================================
  isoImage = {
    # Make the ISO bootable on UEFI systems
    makeEfiBootable = true;

    # Make the ISO bootable on BIOS systems
    makeUsbBootable = true;

    # Compress the ISO image
    squashfsCompression = "zstd";
  };

  # =========================================================================
  # System Settings
  # =========================================================================
  # Automatically start SSH on boot
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

  # Disable password for sudo (useful for automation)
  security.sudo.wheelNeedsPassword = false;
}
