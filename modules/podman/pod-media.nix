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
          };
      };

    # NZBGet secrets - password for web UI authentication
    sops.secrets = lib.genAttrs [
      "nzbget_password"
    ] (_: {
      owner = "poddy";
      group = "poddy";
    });

    sops.templates."nzbget-secrets" = {
      content = ''
        NZBGET_PASS=${config.sops.placeholder."nzbget_password"}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };
  };
}
