{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pods.tools;
  homepageCfg = config.services.pods.homepage;
  # Alternative: inherit (config.services.pods) domain mkTraefikLabels;
  domain = config.services.pods.domain;
  mkTraefikLabels = config.services.pods.mkTraefikLabels;
in
{
  imports = [ ./homepage.nix ];
  options.services.pods.tools = {
    enable = lib.mkEnableOption "Tools pod (homepage dashboard and utilities)";

    homepage = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
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
        default = true;
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
        default = true;
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
        assertion = config.services.pods.reverse-proxy.enable;
        message = "services.pods.tools requires services.pods.reverse-proxy to be enabled (for the reverse_proxy network)";
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
                # Pinned to v1.7.0 - v1.8.0 has SyntaxError bug on icon requests
                image = "ghcr.io/gethomepage/homepage:v1.9.0";
                pod = pods.tools.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "homepage";
                  port = 3000;
                  subdomain = cfg.homepage.subdomain;
                };

                environments = {
                  HOMEPAGE_ALLOWED_HOSTS = "*";
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
                After = [ "tools-pod.service" ];
              };

              containerConfig = {
                image = "ghcr.io/corentinth/it-tools:latest";
                pod = pods.tools.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "it-tools";
                  port = 80;
                  subdomain = cfg.itTools.subdomain;
                  # middlewares = true;  # Uncomment to enable Authelia protection
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
                After = [ "tools-pod.service" ];
              };

              containerConfig = {
                image = "docker.io/amir20/dozzle:latest";
                pod = pods.tools.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "dozzle";
                  port = 8080;
                  subdomain = cfg.dozzle.subdomain;
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
