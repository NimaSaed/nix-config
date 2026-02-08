{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pods.media;
  nixosConfig = config;
  inherit (config.services.pods) domain mkTraefikLabels;
in
{
  options.services.pods.media = {
    enable = lib.mkEnableOption "Media pod (Jellyfin and related services)";

    jellyfin = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Jellyfin media server container in the media pod";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "jellyfin";
        description = "Subdomain for Jellyfin (e.g., jellyfin -> jellyfin.domain)";
      };
    };

    sonarr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable sonarr container in the media pod";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "sonarr";
        description = "Subdomain for sonarr (e.g., sonarr -> sonarr.domain)";
      };
    };

    radarr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable radarr container in the media pod";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "radarr";
        description = "Subdomain for radarr (e.g., radarr -> radarr.domain)";
      };
    };

    nzbget = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable nzbget container in the media pod";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "nzbget";
        description = "Subdomain for nzbget (e.g., nzbget -> nzbget.domain)";
      };
    };

    jellyseerr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable jellyseerr container in the media pod";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "jellyseerr";
        description = "Subdomain for jellyseerr (e.g., jellyseerr -> jellyseerr.domain)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.pods._enabledPods = [ "media" ];

    assertions = [
      {
        assertion = builtins.elem "reverse-proxy" config.services.pods._enabledPods;
        message = "services.pods.media requires Traefik (reverse-proxy) to be configured";
      }
    ];

    home-manager.users.poddy =
      { pkgs, config, ... }:
      {
        virtualisation.quadlet =
          let
            nzbgetSecretsPath = nixosConfig.sops.templates."nzbget-secrets".path;
            inherit (config.virtualisation.quadlet) networks pods volumes;
          in
          {
            volumes.jellyfin_config = {
              volumeConfig = { };
            };
            volumes.jellyfin_cache = {
              volumeConfig = { };
            };

            volumes.sonarr = {
              volumeConfig = { };
            };

            volumes.radarr = {
              volumeConfig = { };
            };

            volumes.nzbget = {
              volumeConfig = { };
            };

            volumes.jellyseerr = {
              volumeConfig = { };
            };

            pods.media = {
              podConfig = {
                networks = [ networks.reverse_proxy.ref ];
              };
            };

            containers.jellyfin = lib.mkIf cfg.jellyfin.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Jellyfin media server container";
                After = [ pods.media.ref ];
              };

              containerConfig = {
                image = "docker.io/jellyfin/jellyfin:latest";
                pod = pods.media.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "jellyfin";
                  port = 8096;
                  subdomain = cfg.jellyfin.subdomain;
                };

                volumes = [
                  "${volumes.jellyfin_cache.ref}:/cache"
                  "${volumes.jellyfin_config.ref}:/config"
                  "/data/media:/media:ro"
                ];

                devices = [ "/dev/dri:/dev/dri" ];
                addGroups = [ "keep-groups" ];
              };
            };
            containers.sonarr = lib.mkIf cfg.sonarr.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Sonarr container";
                After = [ pods.media.ref ];
              };

              containerConfig = {
                image = "lscr.io/linuxserver/sonarr:latest";
                pod = pods.media.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "sonarr";
                  port = 8989;
                  subdomain = cfg.sonarr.subdomain;
                };

                environments = {
                  TZ = "Europe/Amsterdam";
                  PUID = "1001";
                  PGID = "1001";
                };

                volumes = [
                  "${volumes.sonarr.ref}:/config"
                  "/data/media:/media:rw"
                ];

                addGroups = [ "keep-groups" ];
              };
            };

            containers.radarr = lib.mkIf cfg.radarr.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Radarr container";
                After = [ pods.media.ref ];
              };

              containerConfig = {
                image = "lscr.io/linuxserver/radarr:latest";
                pod = pods.media.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "radarr";
                  port = 7878;
                  subdomain = cfg.radarr.subdomain;
                };

                environments = {
                  TZ = "Europe/Amsterdam";
                  PUID = "1001";
                  PGID = "1001";
                };

                volumes = [
                  "${volumes.radarr.ref}:/config"
                  "/data/media:/media:rw"
                ];

                addGroups = [ "keep-groups" ];
              };
            };

            containers.nzbget = lib.mkIf cfg.nzbget.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "NZBGet container";
                After = [ pods.media.ref ];
              };

              containerConfig = {
                image = "lscr.io/linuxserver/nzbget:latest";
                pod = pods.media.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "nzbget";
                  port = 6789;
                  subdomain = cfg.nzbget.subdomain;
                };

                environments = {
                  TZ = "Europe/Amsterdam";
                  PUID = "1001";
                  PGID = "1001";
                  NZBGET_USER = "nzbget";
                };

                environmentFiles = [ nzbgetSecretsPath ];

                volumes = [
                  "${volumes.nzbget.ref}:/config"
                  "/data/media:/media:rw"
                ];

                addGroups = [ "keep-groups" ];
              };
            };

            containers.jellyseerr = lib.mkIf cfg.jellyseerr.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Jellyseerr container";
                After = [ pods.media.ref ];
              };

              containerConfig = {
                image = "docker.io/fallenbagel/jellyseerr:latest";
                pod = pods.media.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "jellyseerr";
                  port = 5055;
                  subdomain = cfg.jellyseerr.subdomain;
                };

                environments = {
                  TZ = "Europe/Amsterdam";
                  LOG_LEVEL = "debug";
                };

                volumes = [
                  "${volumes.jellyseerr.ref}:/app/config"
                ];
              };
            };
          };
      };

    # NZBGet secrets - password for web UI and news server credentials
    sops.secrets = lib.genAttrs [
      "nzbget_password"
      "nzbget_server_host"
      "nzbget_server_username"
      "nzbget_server_password"
    ] (_: {
      owner = "poddy";
      group = "poddy";
    });

    sops.templates."nzbget-secrets" = {
      content = ''
        # Authentication (linuxserver.io specific)
        NZBGET_USER=nzbget
        NZBGET_PASS=${config.sops.placeholder."nzbget_password"}

        # News Server Configuration (NZBOP_ prefix for NZBGet options)
        NZBOP_SERVER1_ACTIVE=yes
        NZBOP_SERVER1_NAME=eweka
        NZBOP_SERVER1_LEVEL=0
        NZBOP_SERVER1_HOST=${config.sops.placeholder."nzbget_server_host"}
        NZBOP_SERVER1_ENCRYPTION=yes
        NZBOP_SERVER1_PORT=563
        NZBOP_SERVER1_USERNAME=${config.sops.placeholder."nzbget_server_username"}
        NZBOP_SERVER1_PASSWORD=${config.sops.placeholder."nzbget_server_password"}
        NZBOP_SERVER1_CONNECTIONS=8
        NZBOP_SERVER1_RETENTION=0

        # Paths
        NZBOP_MAINDIR=/config
        NZBOP_DESTDIR=/media/downloads/completed
        NZBOP_INTERDIR=/media/downloads/intermediate

        # Control Settings
        NZBOP_CONTROLIP=0.0.0.0
        NZBOP_CONTROLPORT=6789
        NZBOP_CONTROLUSERNAME=nzbget
        NZBOP_CONTROLPASSWORD=
        NZBOP_FORMAUTH=yes

        # Performance
        NZBOP_ARTICLECACHE=500
        NZBOP_DIRECTWRITE=yes
        NZBOP_WRITEBUFFER=1024

        # Categories
        NZBOP_CATEGORY1_NAME=Movies
        NZBOP_CATEGORY1_DESTDIR=
        NZBOP_CATEGORY2_NAME=Shows
        NZBOP_CATEGORY2_DESTDIR=
        NZBOP_CATEGORY3_NAME=Music
        NZBOP_CATEGORY3_DESTDIR=
        NZBOP_CATEGORY4_NAME=Software
        NZBOP_CATEGORY4_DESTDIR=

        # Download Queue Settings
        NZBOP_ARTICLERETRIES=3
        NZBOP_POSTSTRATEGY=balanced
        NZBOP_KEEPHISTORY=30

        # Check and Repair
        NZBOP_PARCHECK=auto
        NZBOP_PARREPAIR=yes
        NZBOP_PARSCAN=extended
        NZBOP_HEALTHCHECK=park

        # Unpack
        NZBOP_UNPACK=yes
        NZBOP_UNPACKCLEANUPDISK=yes
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };
  };
}
