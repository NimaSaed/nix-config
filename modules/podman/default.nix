{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.services.pods;
  poddyUid = 1001;
  poddyUidStr = toString poddyUid;
  # Local storage for Podman state (images, DB) - must be local for SQLite locking
  poddyLocalRoot = "/var/lib/poddy";
  # Network storage for volumes (app data) - can be on CIFS share
  poddyDataRoot = "/data/poddy";
  anyPodEnabled = cfg._enabledPods != [ ];
in
{
  imports = [
    inputs.quadlet-nix.nixosModules.quadlet
    ./reverse-proxy.nix
    ./tools.nix
    ./media.nix
    ./auth.nix
  ];

  options.services.pods = {
    _enabledPods = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      internal = true;
      description = "List of enabled pod names (auto-populated by pod modules)";
    };
  };

  config = lib.mkIf anyPodEnabled {
    virtualisation.quadlet.enable = true;

    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;

      autoPrune = {
        enable = true;
        flags = [ "--all" ];
      };
    };

    # Allow rootless Podman to bind to ports 80+
    boot.kernel.sysctl = {
      "net.ipv4.ip_unprivileged_port_start" = 80;
    };

    users.users.poddy = {
      isNormalUser = true;
      description = "Podman container service user";
      home = "/home/poddy";
      createHome = true;
      group = "poddy";
      uid = poddyUid;
      linger = true;
      shell = "${pkgs.shadow}/bin/nologin";
      extraGroups = [ "podman" ];
      autoSubUidGidRange = true;
    };

    users.groups.poddy = { };

    home-manager.users.poddy =
      { pkgs, config, ... }:
      {
        imports = [ inputs.quadlet-nix.homeManagerModules.quadlet ];
        home.stateVersion = "26.05";

        virtualisation.quadlet.autoUpdate = {
          enable = true;
          calendar = "*-*-* 00:00:00";
        };

        xdg.configFile."containers/storage.conf".text = ''
          [storage]
          driver = "overlay"
          runroot = "/run/user/${poddyUidStr}/containers"
          graphroot = "${poddyLocalRoot}/containers/storage"

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

    systemd.tmpfiles.rules = [
      # Local storage for Podman state (images, SQLite DB) - must be local disk
      "d ${poddyLocalRoot} 0750 poddy poddy - -"
      "d ${poddyLocalRoot}/containers 0750 poddy poddy - -"
      "d ${poddyLocalRoot}/containers/storage 0750 poddy poddy - -"
      # Network storage for volumes (app data) - on CIFS share
      "d ${poddyDataRoot} 0750 poddy poddy - -"
      "d ${poddyDataRoot}/containers 0750 poddy poddy - -"
      "d ${poddyDataRoot}/containers/volumes 0750 poddy poddy - -"
    ];
  };
}
