{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pods.media;
  # Alternative: inherit (config.services.pods) domain mkTraefikLabels;
  domain = config.services.pods.domain;
  mkTraefikLabels = config.services.pods.mkTraefikLabels;
in
{
  options.services.pods.media = {
    enable = lib.mkEnableOption "Media pod (Jellyfin and related services)";

    jellyfin = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Jellyfin media server container in the media pod";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "jellyfin";
        description = "Subdomain for Jellyfin (e.g., jellyfin -> jellyfin.domain)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.pods._enabledPods = [ "media" ];

    assertions = [
      {
        assertion = config.services.pods.reverse-proxy.enable;
        message = "services.pods.media requires services.pods.reverse-proxy to be enabled (for the reverse_proxy network)";
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
                After = [ "media-pod.service" ];
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
          };
      };
  };
}
