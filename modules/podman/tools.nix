{ config, lib, pkgs, ... }:

let cfg = config.services.pods.tools;
in {
  options.services.pods.tools = {
    enable = lib.mkEnableOption "Tools pod (homepage dashboard and utilities)";

    homepage = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Homepage dashboard container in the tools pod";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.pods._enabledPods = [ "tools" ];

    assertions = [{
      assertion = config.services.pods.reverse-proxy.enable;
      message =
        "services.pods.tools requires services.pods.reverse-proxy to be enabled (for the reverse_proxy network)";
    }];

    home-manager.users.poddy = { pkgs, config, ... }: {
      virtualisation.quadlet =
        let inherit (config.virtualisation.quadlet) networks pods;
        in {
          pods.tools = {
            podConfig = {
              networks = [ networks.reverse_proxy.ref ];
              publishPorts = [ "3000:3000" ];
            };
          };

          containers.homepage = lib.mkIf cfg.homepage.enable {
            autoStart = true;

            serviceConfig = {
              Restart = "always";
              TimeoutStartSec = 120;
            };

            unitConfig = {
              Description = "Homepage dashboard container";
              After = [ "tools-pod.service" ];
            };

            containerConfig = {
              image = "ghcr.io/gethomepage/homepage:latest";
              pod = pods.tools.ref;

              labels = [
                "io.containers.autoupdate=registry"
                "traefik.enable=true"
                "traefik.http.routers.homepage.rule=Host(`home1.nmsd.xyz`)"
                "traefik.http.routers.homepage.entrypoints=websecure"
                "traefik.http.routers.homepage.tls.certresolver=namecheap"
                "traefik.http.routers.homepage.service=homepage"
                "traefik.http.services.homepage.loadbalancer.server.scheme=http"
                "traefik.http.services.homepage.loadbalancer.server.port=3000"
              ];

              environments = { HOMEPAGE_ALLOWED_HOSTS = "*"; };

              volumes = [ "/data/homepage/config:/app/config" ];

              healthCmd =
                "wget --no-verbose --tries=1 --spider http://tools:3000/api/healthcheck || exit 1";
            };
          };
        };
    };

    systemd.tmpfiles.rules = lib.mkIf cfg.homepage.enable [
      "d /data/homepage 0755 poddy poddy - -"
      "d /data/homepage/config 0755 poddy poddy - -"
    ];
  };
}
