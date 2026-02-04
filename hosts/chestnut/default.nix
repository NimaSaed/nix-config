{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./disko-nvme-btrfs.nix
    ./disko-zfs-datapool.nix
    ./hardware-configuration.nix
    ./samba.nix
    ../common/core
    ../common/users/nima
  ];

  documentation.nixos.enable = false;
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
      itTools.enable = true;
      dozzle.enable = true;
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

  boot.kernelPackages = pkgs.linuxPackages_6_6;

  # Use systemd-boot (EFI only — no BIOS boot partition needed)
  boot.loader.systemd-boot = {
    enable = true;
    consoleMode = "max";
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # ZFS support for datapool (SATA HDDs)
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "datapool" ];

  # Limit ZFS ARC to 8GB - prevent OOM during Colmena builds
  # Default is 50% of RAM (16GB on 32GB system), which starves nix-daemon
  #boot.kernelParams = [
  #  "zfs.zfs_arc_max=8589934592"
  #];

  # ZFS maintenance services
  services.zfs.autoScrub = {
    enable = true;
    interval = "weekly";
  };

  # ZFS auto-snapshots for datapool protection
  services.zfs.autoSnapshot = {
    enable = true;
    frequent = 4; # Every 15 min, keep 4 (1 hour)
    hourly = 24; # Keep 24 hourly
    daily = 7; # Keep 7 daily
    weekly = 4; # Keep 4 weekly
    monthly = 12; # Keep 12 monthly
  };

  # Btrfs scrub for RAID1 data integrity
  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";
    fileSystems = [ "/" ];
  };

  # Periodic TRIM for NVMe SSDs (reclaim unused blocks)
  services.fstrim.enable = true;

  # Enable zram swap for better memory management
  zramSwap.enable = true;
  zramSwap.memoryPercent = 25;

  # ============================================================================
  # Nix Build Settings - Prevent OOM during colmena deploy
  # ============================================================================

  # Limit parallel builds to reduce peak memory usage during deployment
  #nix.settings = {
  #  max-jobs = 2; # Max 2 parallel build jobs (default: auto = all cores)
  #  cores = 2; # Each job uses max 2 cores
  #};

  # Cap nix-daemon memory so builds fail gracefully instead of OOM-killing the system
  #systemd.services.nix-daemon.serviceConfig = {
  #  MemoryHigh = "16G"; # Throttle builds at 16GB (slows down, doesn't kill)
  #  MemoryMax = "20G"; # Hard cap at 20GB (build fails, system survives)
  #};

  # ============================================================================
  # Networking
  # ============================================================================
  # Chestnut - a safe place for your "nuts" (data)
  networking.hostName = "chestnut";
  networking.hostId = "6b2b4dde"; # Required for ZFS (generate with: head -c 8 /etc/machine-id)
  networking.networkmanager.enable = true;

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
  # ESP Sync - Keep backup ESP in sync with primary
  # ============================================================================

  # Sync /boot to /boot-backup after boot and when /boot changes
  systemd.services.esp-sync = {
    description = "Sync primary ESP to backup ESP";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      if mountpoint -q /boot && mountpoint -q /boot-backup; then
        ${pkgs.rsync}/bin/rsync -av --delete --exclude='lost+found' /boot/ /boot-backup/
        echo "ESP sync completed"
      else
        echo "Warning: ESPs not mounted, skipping sync"
      fi
    '';

    path = [ pkgs.util-linux ];
  };

  # Watch /boot for changes and trigger sync
  systemd.paths.esp-sync-watch = {
    description = "Watch /boot for changes";
    wantedBy = [ "multi-user.target" ];

    pathConfig = {
      PathModified = "/boot";
      Unit = "esp-sync.service";
    };
  };

  # Also sync during NixOS activation (nixos-rebuild switch)
  system.activationScripts.esp-sync = lib.stringAfter [ "etc" ] ''
    if mountpoint -q /boot && mountpoint -q /boot-backup; then
      ${pkgs.rsync}/bin/rsync -av --delete --exclude='lost+found' /boot/ /boot-backup/ || true
    fi
  '';

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

  # Create /data directory structure
  # /data owned by root:samby with setgid (2775) so Samba can write via samby group
  # Subdirectories can have different owners
  systemd.tmpfiles.rules = [
    "d /data 2775 root samby - -"
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
    validateSopsFiles = true;

    # Use dedicated age key for decryption
    age.keyFile = "/var/lib/sops-nix/key.txt";
  };

  system.stateVersion = "25.11";
}
