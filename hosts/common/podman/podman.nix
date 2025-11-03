{ config, lib, pkgs, ... }:

{
  # ============================================================================
  # Virtualization - Podman Configuration
  # ============================================================================

  # Enable Podman for container management
  virtualisation.podman = {
    enable = true;
    # Enable Docker compatibility
    dockerCompat = true;
    # Recommended for rootless containers
    defaultNetwork.settings.dns_enabled = true;
  };

  # Enable common container configuration files in /etc/containers
  virtualisation.containers.enable = true;
}
