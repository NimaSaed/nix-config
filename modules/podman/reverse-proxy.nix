{ config, lib, pkgs, ... }:

let
  cfg = config.services.pods.reverse-proxy;
  # Capture NixOS config for use inside Home Manager where 'config' refers to HM config
  nixosConfig = config;
in {
  options.services.pods.reverse-proxy = {
    enable = lib.mkEnableOption "Traefik reverse proxy pod";
    useAcmeStaging = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description =
        "Use Let's Encrypt staging server (for testing, avoids rate limits)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.pods._enabledPods = [ "reverse-proxy" ];

    # Declare secrets this module needs
    sops.secrets = {
      "reverse-proxy/namecheap_email" = {
        owner = "poddy";
        group = "poddy";
      };
      "reverse-proxy/namecheap_api_user" = {
        owner = "poddy";
        group = "poddy";
      };
      "reverse-proxy/namecheap_api_key" = {
        owner = "poddy";
        group = "poddy";
      };
    };

    networking.firewall = { allowedTCPPorts = [ 80 443 ]; };

    home-manager.users.poddy = { pkgs, config, ... }: {
      virtualisation.quadlet = let
        secretsPath = nixosConfig.sops.templates."traefik-secrets".path;
        inherit (config.virtualisation.quadlet) networks pods volumes;
      in {
        volumes.traefik = { volumeConfig = { }; };
        networks.reverse_proxy = {
          networkConfig = { name = "reverse_proxy"; };
        };

        pods.reverse_proxy = {
          podConfig = {
            networks = [ networks.reverse_proxy.ref ];
            publishPorts = [ "80:80" "443:443" "8080:8080" "636:636" ];
          };
        };

        containers.traefik = {
          autoStart = true;

          serviceConfig = {
            Restart = "always";
            TimeoutStartSec = 120;
          };

          unitConfig = {
            Description = "Traefik reverse proxy container";
            After = [ "reverse_proxy-pod.service" ];
          };

          containerConfig = {
            image = "docker.io/library/traefik:latest";
            pod = pods.reverse_proxy.ref;

            labels = [
              "io.containers.autoupdate=registry"
              "traefik.enable=true"
              "traefik.http.routers.traefik.rule=Host(`traefik1.nmsd.xyz`)"
              "traefik.http.routers.traefik.entrypoints=websecure"
              "traefik.http.routers.traefik.tls=true"
              "traefik.http.routers.traefik.tls.certresolver=namecheap"
              "traefik.http.routers.traefik.service=api@internal"
            ];

            # %t = XDG_RUNTIME_DIR
            volumes = [
              "%t/podman/podman.sock:/var/run/docker.sock:ro"
              "${volumes.traefik.ref}:/data"
            ];

            environmentFiles = [ secretsPath ];

            environments = {
              TRAEFIK_LOG_LEVEL = "DEBUG";
              TRAEFIK_PROVIDERS_DOCKER = "true";
              TRAEFIK_PROVIDERS_DOCKER_EXPOSEDBYDEFAULT = "false";
              TRAEFIK_API = "true";
              TRAEFIK_API_DASHBOARD = "true";
              TRAEFIK_API_INSECURE = "true";
              TRAEFIK_ENTRYPOINTS_WEB_ADDRESS = ":80";
              TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS = ":443";
              TRAEFIK_ENTRYPOINTS_LLDAPSECURE_ADDRESS = ":636";
              TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_TO =
                "websecure";
              TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_SCHEME =
                "https";
              TRAEFIK_CERTIFICATESRESOLVERS_NAMECHEAP_ACME_DNSCHALLENGE =
                "true";
              TRAEFIK_CERTIFICATESRESOLVERS_NAMECHEAP_ACME_DNSCHALLENGE_PROVIDER =
                "namecheap";
              TRAEFIK_CERTIFICATESRESOLVERS_NAMECHEAP_ACME_DNSCHALLENGE_RESOLVERS =
                "1.1.1.1:53,198.54.117.10:53,198.54.117.11:53";
              TRAEFIK_CERTIFICATESRESOLVERS_NAMECHEAP_ACME_STORAGE =
                "/data/acme.json";
              TRAEFIK_SERVERSTRANSPORT_INSECURESKIPVERIFY = "true";
            } // lib.optionalAttrs cfg.useAcmeStaging {
              TRAEFIK_CERTIFICATESRESOLVERS_NAMECHEAP_ACME_CASERVER =
                "https://acme-staging-v02.api.letsencrypt.org/directory";
            };

            securityLabelType = "container_runtime_t";
          };
        };
      };
    };

    sops.templates."traefik-secrets" = {
      content = ''
        TRAEFIK_CERTIFICATESRESOLVERS_NAMECHEAP_ACME_EMAIL=${
          config.sops.placeholder."reverse-proxy/namecheap_email"
        }
        NAMECHEAP_API_USER=${
          config.sops.placeholder."reverse-proxy/namecheap_api_user"
        }
        NAMECHEAP_API_KEY=${
          config.sops.placeholder."reverse-proxy/namecheap_api_key"
        }
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };
  };
}
