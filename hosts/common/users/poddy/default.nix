{ config, lib, pkgs, ... }:

let
  poddyUid = toString config.users.users.poddy.uid;
  poddyDataRoot = "/data/poddy";
in
{
  # ============================================================================
  # Poddy User - Dedicated user for rootless Podman containers
  # ============================================================================
  # This user runs all containerized services in rootless mode for improved
  # security isolation. Systemd user services are enabled via lingering.
  # All Podman data is stored on ZFS datapool at /data/poddy

  users.users.poddy = {
    isNormalUser = true;
    description = "Podman container service user";
    home = "/home/poddy";
    createHome = true;
    group = "poddy";

    # Disable interactive login for security
    # User only needs systemd service access (via lingering)
    shell = pkgs.nologin;

    # Required for rootless Podman networking and port binding
    extraGroups = [ "podman" ];

    # Subuid and subgid ranges for user namespace mapping
    # Required for rootless containers
    subUidRanges = [{
      startUid = 100000;
      count = 65536;
    }];
    subGidRanges = [{
      startGid = 100000;
      count = 65536;
    }];
  };

  users.groups.poddy = { };

  # ============================================================================
  # Systemd User Service Lingering
  # ============================================================================
  # Enable lingering so systemd user services start at boot and persist
  # even when the user is not logged in. Essential for container services.
  systemd.tmpfiles.rules = [
    # Systemd lingering
    "d /var/lib/systemd/linger 0755 root root - -"
    "f /var/lib/systemd/linger/poddy 0644 root root - -"

    # Create Podman data directories on ZFS datapool
    "d ${poddyDataRoot} 0750 poddy poddy - -"
    "d ${poddyDataRoot}/containers 0750 poddy poddy - -"
    "d ${poddyDataRoot}/containers/storage 0750 poddy poddy - -"
    "d ${poddyDataRoot}/containers/volumes 0750 poddy poddy - -"
    "d ${poddyDataRoot}/config 0750 poddy poddy - -"
    "d ${poddyDataRoot}/config/containers 0750 poddy poddy - -"
    "d ${poddyDataRoot}/config/systemd 0750 poddy poddy - -"
    "d ${poddyDataRoot}/config/systemd/user 0750 poddy poddy - -"

    # Create user-specific Podman configuration files
    "L+ ${poddyDataRoot}/config/containers/storage.conf - - - - ${pkgs.writeText "poddy-storage.conf" ''
      [storage]
      driver = "overlay"
      runroot = "/run/user/${poddyUid}/containers"
      graphroot = "${poddyDataRoot}/containers/storage"

      [storage.options]
      # Use fuse-overlayfs for rootless overlay mounts
      mount_program = "${pkgs.fuse-overlayfs}/bin/fuse-overlayfs"
    ''}"

    "L+ ${poddyDataRoot}/config/containers/containers.conf - - - - ${pkgs.writeText "poddy-containers.conf" ''
      [engine]
      # Custom volume path on ZFS datapool
      volume_path = "${poddyDataRoot}/containers/volumes"

      # Number of locks for container operations
      num_locks = 2048

      [network]
      # Default network backend for rootless containers
      network_backend = "netavark"
    ''}"
  ];

  # ============================================================================
  # XDG Runtime Directory
  # ============================================================================
  # Ensure XDG_RUNTIME_DIR exists for systemd user services
  # This is where Podman stores its socket and temporary files
  systemd.services."user-runtime-dir@".serviceConfig = {
    RuntimeDirectory = "user/%i";
    RuntimeDirectoryMode = "0700";
  };

  # ============================================================================
  # XDG Environment Variables Override for Podman User
  # ============================================================================
  # Override XDG directories to point to ZFS datapool for data persistence
  # This moves all Podman data (images, containers, volumes, config) to /data
  systemd.services."user@${poddyUid}".serviceConfig = {
    Environment = [
      "XDG_CONFIG_HOME=${poddyDataRoot}/config"
      "XDG_DATA_HOME=${poddyDataRoot}/containers"
    ];
  };
}
