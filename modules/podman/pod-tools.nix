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

    changedetection = {
      enable = lib.mkEnableOption "changedetection.io website change monitor in the tools pod";
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "changedetection";
        description = "Subdomain for changedetection.io";
      };
      browser = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Run the sockpuppetbrowser sidecar so changedetection.io can fetch
          JavaScript-rendered pages. Costs extra memory (a Chromium process per
          concurrent browser-backed fetch); disable for plain HTTP fetching only.
        '';
      };
      fetchWorkers = lib.mkOption {
        type = lib.types.ints.positive;
        default = 10;
        description = ''
          Number of parallel fetchers (FETCH_WORKERS). Lower this on
          resource-constrained hosts, especially when the browser sidecar is on.
        '';
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
            inherit (config.virtualisation.quadlet) networks pods volumes;
          in
          {
            volumes.tools_changedetection = lib.mkIf cfg.changedetection.enable {
              volumeConfig = { };
            };

            pods.tools = {
              podConfig = {
                networks = [ networks.reverse_proxy.ref ];
              };
            };

            containers.tools-homepage = lib.mkIf cfg.homepage.enable {
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

            containers.tools-ittools = lib.mkIf cfg.itTools.enable {
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

            containers.tools-dozzle = lib.mkIf cfg.dozzle.enable {
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

            containers.tools-changedetection = lib.mkIf cfg.changedetection.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "changedetection.io website change monitor container";
                After = [ pods.tools.ref ];
              };

              containerConfig = {
                image = "ghcr.io/dgtlmoon/changedetection.io:latest";
                pod = pods.tools.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "changedetection";
                  port = 5000;
                  subdomain = cfg.changedetection.subdomain;
                  middlewares = true;
                };

                environments = {
                  BASE_URL = "https://${cfg.changedetection.subdomain}.${domain}";
                  # Honour X-Forwarded-* headers from Traefik.
                  USE_X_SETTINGS = "1";
                  FETCH_WORKERS = toString cfg.changedetection.fetchWorkers;
                  DISABLE_VERSION_CHECK = "true";
                }
                // lib.optionalAttrs cfg.changedetection.browser {
                  # Sidecar shares the pod's network namespace, reachable on localhost.
                  PLAYWRIGHT_DRIVER_URL = "ws://127.0.0.1:3000";
                };

                volumes = [
                  "${volumes.tools_changedetection.ref}:/datastore"
                ];
              };
            };

            containers.tools-changedetection-browser =
              lib.mkIf (cfg.changedetection.enable && cfg.changedetection.browser)
                {
                  autoStart = true;

                  serviceConfig = {
                    Restart = "always";
                    TimeoutStopSec = 70;
                  };

                  unitConfig = {
                    Description = "Sockpuppet browser for changedetection.io";
                    After = [ pods.tools.ref ];
                  };

                  containerConfig = {
                    image = "docker.io/dgtlmoon/sockpuppetbrowser:latest";
                    pod = pods.tools.ref;
                    autoUpdate = "registry";

                    # Chromium needs a larger /dev/shm than the default 64M.
                    shmSize = "2g";

                    environments = {
                      SCREEN_WIDTH = "1920";
                      SCREEN_HEIGHT = "1024";
                      SCREEN_DEPTH = "16";
                      MAX_CONCURRENT_CHROME_PROCESSES = toString cfg.changedetection.fetchWorkers;
                    };
                  };
                };
          };
      };

  };
}
