{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pods.media;
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
            inherit (config.virtualisation.quadlet) networks pods volumes;
          in
          {
            volumes.jellyfin_config = {
              volumeConfig = { };
            };
            volumes.jellyfin_cache = {
              volumeConfig = { };
            };
            volumes.media = {
              volumeConfig = {
                Type = "bind";
                Device = "/data/media";
              };
            };
            volumes.sonarr = {
              volumeConfig = { };
            }
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
                  "${volumes.media.ref}:/media:ro"
                ];

                podmanArgs = [ "--device=/dev/dri:/dev/dri" ];
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
                  "${volumes.media.ref}:/media:rw"
                ];

                podmanArgs = [ "--device=/dev/dri:/dev/dri" ];
              };
            };
          };
      };
  };
}
