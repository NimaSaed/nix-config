{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.services.pods;
  poddyUid = 1001;
  poddyUidStr = toString poddyUid;
  poddyDataRoot = "/data/poddy";
  anyPodEnabled = cfg._enabledPods != [ ];
in {
  imports =
    [ inputs.quadlet-nix.nixosModules.quadlet ./reverse-proxy.nix ./tools.nix ];

  # ============================================================================
  # Module Options
  # ============================================================================
  options.services.pods = {
    _enabledPods = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      internal = true;
      description = "List of enabled pod names (auto-populated by pod modules)";
    };
  };

  # ============================================================================
  # Module Configuration
  # ============================================================================
  config = lib.mkIf anyPodEnabled {
    # ==========================================================================
    # Virtualization - Podman Configuration
    # ==========================================================================

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

      # ========================================================================
      # Auto-Prune: Automatically remove unused images
      # ========================================================================
      # Removes dangling images and unused containers weekly to free up disk space
      autoPrune = {
        enable = true;
        flags = [ "--all" ]; # Remove all unused images, not just dangling ones
      };
    };

    # ==========================================================================
    # Sysctl: Allow Rootless Podman to Bind to Privileged Ports
    # ==========================================================================
    # By default, only root can bind to ports below 1024 (privileged ports).
    # This setting allows unprivileged users to bind to ports starting from 80,
    # enabling rootless Podman to expose services on standard HTTP (80) and HTTPS (443) ports.
    #
    # Security note: This is safe for rootless containers because they still run
    # within user namespaces with proper UID/GID mapping configured via subuid/subgid.
    boot.kernel.sysctl = { "net.ipv4.ip_unprivileged_port_start" = 80; };

    # ==========================================================================
    # Poddy User - Dedicated user for rootless Podman containers
    # ==========================================================================
    # This user runs all containerized services in rootless mode for improved
    # security isolation. Systemd user services are enabled via lingering.
    # All Podman data is stored on ZFS datapool at /data/poddy

    users.users.poddy = {
      isNormalUser = true;
      description = "Podman container service user";
      home = "/home/poddy";
      createHome = true;
      group = "poddy";
      uid = poddyUid;

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

    # ==========================================================================
    # Home Manager Configuration for poddy user
    # ==========================================================================
    # Configure Home Manager for the poddy user with quadlet-nix support.
    # This enables declarative management of rootless Podman containers.
    home-manager.users.poddy = { pkgs, config, ... }: {
      imports = [ inputs.quadlet-nix.homeManagerModules.quadlet ];
      home.stateVersion = "25.05";

      # Enable podman auto-update for rootless containers
      # Runs daily at midnight to update containers with AutoUpdate=registry label
      # Note: Individual containers need autoUpdate = "registry" in their config
      virtualisation.quadlet = {
        enablePodmanAutoUpdate = true;
        podmanAutoUpdateSchedule = "*-*-* 00:00:00"; # Daily at midnight
      };

      # Configure storage paths on ZFS datapool
      xdg.configFile."containers/storage.conf".text = ''
        [storage]
        driver = "overlay"
        runroot = "/run/user/${poddyUidStr}/containers"
        graphroot = "${poddyDataRoot}/containers/storage"

        [storage.options]
        mount_program = "${pkgs.fuse-overlayfs}/bin/fuse-overlayfs"
      '';

      xdg.configFile."containers/containers.conf".text = ''
        [engine]
        volume_path = "${poddyDataRoot}/containers/volumes"
        num_locks = 2048

        [network]
        network_backend = "netavark"
      '';
    };

    # ==========================================================================
    # Podman Data Directories
    # ==========================================================================
    # Create Podman data directories on ZFS datapool
    # Configuration files are managed by Home Manager via xdg.configFile
    systemd.tmpfiles.rules = [
      "d ${poddyDataRoot} 0750 poddy poddy - -"
      "d ${poddyDataRoot}/containers 0750 poddy poddy - -"
      "d ${poddyDataRoot}/containers/storage 0750 poddy poddy - -"
      "d ${poddyDataRoot}/containers/volumes 0750 poddy poddy - -"
    ];
  };
}
