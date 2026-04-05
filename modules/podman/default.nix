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
  poddyGid = 1001;
  poddyUidStr = toString poddyUid;
  poddyLocalRoot = "/var/lib/poddy";
  poddyDataRoot = "/data/containers";
  anyPodEnabled = cfg._enabledPods != [ ];

  # Helper function to generate consistent Traefik labels for containers
  mkTraefikLabels =
    {
      name,
      port,
      subdomain ? name,
      scheme ? "http",
      middlewares ? false,
      # Function that receives `name` and returns extra labels attrset
      # Usage: extraLabels = name: { "traefik.tcp.routers.${name}.rule" = "..."; }
      # Default: (_: { }) = function that ignores arg and returns empty attrset
      extraLabels ? (_: { }),
    }:
    let
      resolvedMiddleware =
        if middlewares == true then
          "authelia@docker"
        else if middlewares == false then
          null
        else
          middlewares;
    in
    {
      "traefik.enable" = "true";
      "traefik.http.routers.${name}.rule" = "Host(`${subdomain}.${cfg.domain}`)";
      "traefik.http.routers.${name}.entrypoints" = "websecure";
      "traefik.http.routers.${name}.tls" = "true";
      "traefik.http.routers.${name}.tls.certresolver" = "letsencrypt";
      "traefik.http.routers.${name}.service" = name;
      "traefik.http.services.${name}.loadbalancer.server.scheme" = scheme;
      "traefik.http.services.${name}.loadbalancer.server.port" = toString port;
    }
    // lib.optionalAttrs (resolvedMiddleware != null) {
      "traefik.http.routers.${name}.middlewares" = resolvedMiddleware;
    }
    // (extraLabels name);
in
{
  imports = [
    inputs.quadlet-nix.nixosModules.quadlet
    ./pod-reverse-proxy.nix
    ./pod-auth.nix
    ./pod-tools.nix
    ./pod-media.nix
    ./pod-nextcloud.nix
    ./pod-smart-home.nix
    ./pod-immich.nix
    ./pod-ai.nix
    ./pod-vaultwarden.nix
  ];

  options.services.pods = {
    domain = lib.mkOption {
      type = lib.types.str;
      default = "example.com";
      example = "mydomain.org";
      description = "Base domain for all pod services (e.g., example.com)";
    };

    mkTraefikLabels = lib.mkOption {
      type = lib.types.functionTo lib.types.attrs;
      default = mkTraefikLabels;
      internal = true;
      description = "Helper function to generate Traefik labels for containers";
    };

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
      extraGroups = [
        "podman"
        "render"
        "video"
      ];
      autoSubUidGidRange = true;
    };

    users.groups.poddy = {
      gid = poddyGid;
    };

    home-manager.users.poddy =
      { pkgs, config, ... }:
      {
        imports = [ inputs.quadlet-nix.homeManagerModules.quadlet ];
        home.stateVersion = "25.11";

        virtualisation.quadlet.autoUpdate = {
          enable = true;
          calendar = "*-*-* 00:00:00";
        };

        xdg.configFile."containers/storage.conf".text = ''
          [storage]
          driver = "overlay"
          runroot = "/run/user/${poddyUidStr}/containers"
          graphroot = "${poddyLocalRoot}/containers/storage"
        '';

        xdg.configFile."containers/containers.conf".text = ''
          [engine]
          volume_path = "${poddyDataRoot}/volumes"
          num_locks = 2048

          [network]
          network_backend = "netavark"
        '';

        systemd.user.services.podman-auto-prune = {
          description = "Podman auto prune unused images";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.podman}/bin/podman image prune --all --force";
          };
        };

        systemd.user.timers.podman-auto-prune = {
          description = "Podman auto prune timer";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
          };
        };
      };

    systemd.tmpfiles.rules = [
      "d ${poddyLocalRoot} 0750 poddy poddy - -"
      "d ${poddyLocalRoot}/containers 0750 poddy poddy - -"
      "d ${poddyLocalRoot}/containers/storage 0750 poddy poddy - -"
      "d ${poddyDataRoot} 0755 poddy poddy - -"
      "d ${poddyDataRoot}/volumes 0755 poddy poddy - -"
    ];
  };
}
