{ config, lib, pkgs, ... }:

let
  poddyUid = "1001";  # Fixed UID for poddy user
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
    uid = 1001;  # Fixed UID to match configuration

    # Enable lingering so systemd user services start at boot
    # This is the proper declarative NixOS way to enable lingering
    linger = true;

    # Disable interactive login for security
    # User only needs systemd service access (via lingering)
    shell = "${pkgs.shadow}/bin/nologin";

    # Required for rootless Podman networking and port binding
    extraGroups = [ "podman" ];

    # Auto-allocate subuid/subgid ranges for rootless containers
    # This is the recommended approach for quadlet-nix
    autoSubUidGidRange = true;
  };

  users.groups.poddy = { };

  # ============================================================================
  # Podman Data Directories
  # ============================================================================
  # Create Podman data directories and configuration files on ZFS datapool
  # Note: /run/user/1001 is managed by systemd-logind via lingering, not tmpfiles
  systemd.tmpfiles.rules = [
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
  # Activation Script - Ensure Podman Directories Exist
  # ============================================================================
  # This activation script ensures tmpfiles are created before user services start
  # It runs during system activation (nixos-rebuild switch)
  system.activationScripts.setupPoddyDirectories = {
    deps = [ "users" "specialfs" ];
    text = ''
      # Create tmpfiles for poddy user before starting services
      ${pkgs.systemd}/bin/systemd-tmpfiles --create --prefix=${poddyDataRoot}

      # Ensure runtime directory exists via systemd-logind
      # This triggers lingering to create /run/user/1001 if it doesn't exist
      if [ ! -d "/run/user/${poddyUid}" ]; then
        ${pkgs.systemd}/bin/loginctl enable-linger poddy || true
        # Wait a moment for logind to create the directory
        for i in {1..10}; do
          [ -d "/run/user/${poddyUid}" ] && break
          sleep 0.5
        done
      fi
    '';
  };
}
