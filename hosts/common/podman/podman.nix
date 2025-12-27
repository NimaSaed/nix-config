{ config, lib, pkgs, ... }:

{
  # ============================================================================
  # Virtualization - Podman Configuration
  # ============================================================================

  # Enable Quadlet NixOS module for declarative container management
  # Required by quadlet-nix for rootless Home Manager containers
  virtualisation.quadlet.enable = true;

  # Enable Podman for container management
  virtualisation.podman = {
    enable = true;
    # Enable Docker compatibility
    dockerCompat = true;
    # Recommended for rootless containers
    defaultNetwork.settings.dns_enabled = true;

    # ============================================================================
    # Auto-Prune: Automatically remove unused images
    # ============================================================================
    # Removes dangling images and unused containers weekly to free up disk space
    autoPrune = {
      enable = true;
      flags = [ "--all" ]; # Remove all unused images, not just dangling ones
    };
  };

  # Enable common container configuration files in /etc/containers
  virtualisation.containers.enable = true;

  # ============================================================================
  # Sysctl: Allow Rootless Podman to Bind to Privileged Ports
  # ============================================================================
  # By default, only root can bind to ports below 1024 (privileged ports).
  # This setting allows unprivileged users to bind to ports starting from 80,
  # enabling rootless Podman to expose services on standard HTTP (80) and HTTPS (443) ports.
  #
  # Security note: This is safe for rootless containers because they still run
  # within user namespaces with proper UID/GID mapping configured via subuid/subgid.
  boot.kernel.sysctl = { "net.ipv4.ip_unprivileged_port_start" = 80; };

  # ============================================================================
  # Podman Auto-Update: Automatically update containers with registry label
  # ============================================================================
  # This enables the native podman-auto-update systemd timer and service.
  # Runs daily at midnight to check for and pull updated container images.
  #
  # REQUIREMENTS FOR CONTAINERS:
  # 1. Containers must be labeled with: io.containers.autoupdate=registry
  # 2. Images must use fully-qualified references (e.g., docker.io/library/nginx:latest)
  # 3. Containers should be managed as systemd services
  #
  # Example container with auto-update:
  #   podman run -d \
  #     --label "io.containers.autoupdate=registry" \
  #     --name myapp \
  #     docker.io/library/nginx:latest
  #
  # Or in NixOS using virtualisation.oci-containers:
  #   virtualisation.oci-containers.containers.myapp = {
  #     image = "docker.io/library/nginx:latest";
  #     labels = { "io.containers.autoupdate" = "registry"; };
  #   };
  #
  # FEATURES:
  # - Automatic rollback if updated container fails to start
  # - Only updates containers with the autoupdate label
  # - Manual trigger: systemctl start podman-auto-update.service
  # - Dry-run: podman auto-update --dry-run

  systemd.timers.podman-auto-update = {
    description = "Podman Auto-Update Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily"; # Run once per day at midnight
      Persistent = true; # Run on boot if missed while powered off
      RandomizedDelaySec = "15min"; # Add random delay to prevent load spikes
    };
  };

  systemd.services.podman-auto-update = {
    description = "Podman Auto-Update Service";
    documentation = [ "man:podman-auto-update(1)" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.podman}/bin/podman auto-update";
      ExecStartPost =
        "${pkgs.podman}/bin/podman image prune -f"; # Clean up old images after update
    };
  };
}
