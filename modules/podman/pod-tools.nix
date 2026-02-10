{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pods.tools;
  homepageCfg = config.services.pods.homepage;
  inherit (config.services.pods) domain mkTraefikLabels;
in
{
  imports = [ ./container-configs/homepage.nix ];
  options.services.pods.tools = {
    enable = lib.mkEnableOption "Tools pod (homepage dashboard and utilities)";

    homepage = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Homepage dashboard container in the tools pod";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "homepage";
        description = "Subdomain for Homepage dashboard";
      };
    };

    itTools = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable IT Tools container in the tools pod";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "it-tools";
        description = "Subdomain for IT Tools";
      };
    };

    dozzle = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Dozzle log viewer container in the tools pod";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "dozzle";
        description = "Subdomain for Dozzle log viewer";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.pods._enabledPods = [ "tools" ];

    assertions = [
      {
        assertion = builtins.elem "reverse-proxy" config.services.pods._enabledPods;
        message = "services.pods.tools requires Traefik (reverse-proxy) to be configured";
      }
    ];

    home-manager.users.poddy =
      { pkgs, config, ... }:
      {
        virtualisation.quadlet =
          let
            inherit (config.virtualisation.quadlet) networks pods;
          in
          {
            pods.tools = {
              podConfig = {
                networks = [ networks.reverse_proxy.ref ];
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
                After = [ pods.tools.ref ];
              };

              containerConfig = {
                image = "ghcr.io/gethomepage/homepage:latest";
                pod = pods.tools.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "homepage";
                  port = 3000;
                  subdomain = cfg.homepage.subdomain;
                  middlewares = true;
                };

                environments = {
                  HOMEPAGE_ALLOWED_HOSTS = "${cfg.homepage.subdomain}.${domain},tools:3000";
                };

                volumes = [
                  "${homepageCfg.settingsFile}:/app/config/settings.yaml:ro"
                  "${homepageCfg.servicesFile}:/app/config/services.yaml:ro"
                  "${homepageCfg.bookmarksFile}:/app/config/bookmarks.yaml:ro"
                  "${homepageCfg.widgetsFile}:/app/config/widgets.yaml:ro"
                  "${homepageCfg.dockerFile}:/app/config/docker.yaml:ro"
                  "${homepageCfg.kubernetesFile}:/app/config/kubernetes.yaml:ro"
                  "${homepageCfg.proxmoxFile}:/app/config/proxmox.yaml:ro"
                  "${homepageCfg.customCssFile}:/app/config/custom.css:ro"
                  "${homepageCfg.customJsFile}:/app/config/custom.js:ro"
                ];

                healthCmd = "wget --no-verbose --tries=1 --spider http://tools:3000/api/healthcheck || exit 1";
              };
            };

            containers.it_tools = lib.mkIf cfg.itTools.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "IT Tools container";
                After = [ pods.tools.ref ];
              };

              containerConfig = {
                image = "ghcr.io/corentinth/it-tools:latest";
                pod = pods.tools.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "it-tools";
                  port = 80;
                  subdomain = cfg.itTools.subdomain;
                };
              };
            };

            containers.dozzle = lib.mkIf cfg.dozzle.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Dozzle log viewer container";
                After = [ pods.tools.ref ];
              };

              containerConfig = {
                image = "docker.io/amir20/dozzle:latest";
                pod = pods.tools.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "dozzle";
                  port = 8080;
                  subdomain = cfg.dozzle.subdomain;
                  middlewares = true;
                };

                environments = {
                  DOZZLE_NO_ANALYTICS = "true";
                };

                volumes = [
                  "%t/podman/podman.sock:/var/run/docker.sock:ro"
                ];
              };
            };
          };
      };

  };
}
