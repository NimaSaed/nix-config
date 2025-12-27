{ config, lib, pkgs, ... }:

{
  home-manager.users.poddy = { pkgs, config, ... }: {
    virtualisation.quadlet = let
      inherit (config.virtualisation.quadlet) pods;
    in {
      containers.homepage = {
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
            #"traefik.http.routers.homepage.middlewares=authelia"
          ];

          environments = {
            HOMEPAGE_ALLOWED_HOSTS = "*";
          };

          volumes = [
            "/data/homepage/config:/app/config"
          ];

          healthCmd = "wget --no-verbose --tries=1 --spider http://localhost:3000/api/healthcheck || exit 1";
        };
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /data/homepage 0755 poddy poddy - -"
    "d /data/homepage/config 0755 poddy poddy - -"
  ];
}
