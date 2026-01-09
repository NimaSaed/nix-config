{ config, lib, pkgs, ... }:

let
  cfg = config.services.pods.media;
  jellyfinDataRoot = "/data/jellyfin";
  mediaRoot = "/data/media";
in {
  options.services.pods.media = {
    enable = lib.mkEnableOption "Media pod (Jellyfin and related services)";

    jellyfin = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Jellyfin media server container in the media pod";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.pods._enabledPods = [ "media" ];

    assertions = [{
      assertion = config.services.pods.reverse-proxy.enable;
      message =
        "services.pods.media requires services.pods.reverse-proxy to be enabled (for the reverse_proxy network)";
    }];

    systemd.tmpfiles.rules = [
      "d ${jellyfinDataRoot} 0750 poddy poddy - -"
      "d ${jellyfinDataRoot}/config 0750 poddy poddy - -"
      "d ${jellyfinDataRoot}/cache 0750 poddy poddy - -"
    ];

    home-manager.users.poddy = { pkgs, config, ... }: {
      virtualisation.quadlet =
        let inherit (config.virtualisation.quadlet) networks pods;
        in {
          pods.media = {
            podConfig = {
              networks = [ networks.reverse_proxy.ref ];
              publishPorts = [ "8096:8096" ];
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

              labels = {
                "traefik.enable" = "true";
                "traefik.http.routers.media.rule" = "Host(`media1.nmsd.xyz`)";
                "traefik.http.routers.media.entrypoints" = "websecure";
                "traefik.http.routers.media.tls.certresolver" = "namecheap";
                "traefik.http.routers.media.service" = "media";
                "traefik.http.services.media.loadbalancer.server.scheme" =
                  "http";
                "traefik.http.services.media.loadbalancer.server.port" = "8096";
              };

              volumes = [
                "${jellyfinDataRoot}/cache:/cache"
                "${jellyfinDataRoot}/config:/config"
                "${mediaRoot}:/media:ro"
              ];

              addDevice = [ "/dev/dri:/dev/dri" ];
            };
          };
        };
    };
  };
}
