{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.services.pods;
  poddyUid = 1001;
  poddyUidStr = toString poddyUid;
  poddyDataRoot = "/data/poddy";
  anyPodEnabled = cfg._enabledPods != [];
in {
  imports = [
    inputs.quadlet-nix.nixosModules.quadlet
    ./reverse-proxy.nix
    ./tools.nix
  ];

  # ============================================================================
  # Module Options
  # ============================================================================
  options.services.pods = {
    _enabledPods = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
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

    # Enable common container configuration files in /etc/containers
    virtualisation.containers.enable = true;

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
    # Podman Auto-Update: Automatically update containers with registry label
    # ==========================================================================
    # This enables the native podman-auto-update systemd timer and service.
    # Runs daily at midnight to check for and pull updated container images.
    #
    # REQUIREMENTS FOR CONTAINERS:
    # 1. Containers must be labeled with: io.containers.autoupdate=registry
    # 2. Images must use fully-qualified references (e.g., docker.io/library/nginx:latest)
    # 3. Containers should be managed as systemd services
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
    };

    # ==========================================================================
    # Podman Data Directories
    # ==========================================================================
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
      "L+ ${poddyDataRoot}/config/containers/storage.conf - - - - ${
        pkgs.writeText "poddy-storage.conf" ''
          [storage]
          driver = "overlay"
          runroot = "/run/user/${poddyUidStr}/containers"
          graphroot = "${poddyDataRoot}/containers/storage"

          [storage.options]
          # Use fuse-overlayfs for rootless overlay mounts
          mount_program = "${pkgs.fuse-overlayfs}/bin/fuse-overlayfs"
        ''
      }"

      "L+ ${poddyDataRoot}/config/containers/containers.conf - - - - ${
        pkgs.writeText "poddy-containers.conf" ''
          [engine]
          # Custom volume path on ZFS datapool
          volume_path = "${poddyDataRoot}/containers/volumes"

          # Number of locks for container operations
          num_locks = 2048

          [network]
          # Default network backend for rootless containers
          network_backend = "netavark"
        ''
      }"
    ];

    # ==========================================================================
    # XDG Runtime Directory
    # ==========================================================================
    # Ensure XDG_RUNTIME_DIR exists for systemd user services
    # This is where Podman stores its socket and temporary files
    systemd.services."user-runtime-dir@".serviceConfig = {
      RuntimeDirectory = "user/%i";
      RuntimeDirectoryMode = "0700";
    };

    # ==========================================================================
    # Activation Script - Ensure Podman Directories Exist
    # ==========================================================================
    # This activation script ensures tmpfiles are created before user services start
    # It runs during system activation (nixos-rebuild switch)
    system.activationScripts.setupPoddyDirectories = {
      deps = [ "users" "specialfs" ];
      text = ''
        # Create tmpfiles for poddy user before starting services
        ${pkgs.systemd}/bin/systemd-tmpfiles --create --prefix=${poddyDataRoot}

        # Ensure runtime directory exists via systemd-logind
        # This triggers lingering to create /run/user/1001 if it doesn't exist
        if [ ! -d "/run/user/${poddyUidStr}" ]; then
          ${pkgs.systemd}/bin/loginctl enable-linger poddy || true
          # Wait a moment for logind to create the directory
          for i in {1..10}; do
            [ -d "/run/user/${poddyUidStr}" ] && break
            sleep 0.5
          done
        fi
      '';
    };
  };
}
