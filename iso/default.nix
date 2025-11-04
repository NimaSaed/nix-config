# Minimal NixOS Installer ISO Configuration
# This creates a bootable ISO with SSH access for remote deployment
{ config, pkgs, lib, modulesPath, ... }:

{
  # nixos-generators automatically imports the appropriate base configuration
  # based on the format parameter (install-iso, sd-aarch64-installer, etc.)
  imports = [ ];

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
    git # For cloning configurations
    vim # Text editor
  ];

  # =========================================================================
  # System Settings
  # =========================================================================
  # Automatically start SSH on boot
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

  # Disable password for sudo (useful for automation)
  security.sudo.wheelNeedsPassword = false;
}
