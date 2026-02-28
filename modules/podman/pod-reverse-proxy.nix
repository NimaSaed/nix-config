{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pods.reverse-proxy;
  inherit (config.services.pods) domain mkTraefikLabels;
  nixosConfig = config;
in
{
  options.services.pods.reverse-proxy = {
    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "traefik";
      description = "Subdomain for Traefik dashboard";
    };
    useAcmeStaging = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use Let's Encrypt staging server (for testing, avoids rate limits)";
    };
  };

  config = {
    services.pods._enabledPods = [ "reverse-proxy" ];

    # Declare secrets this module needs
    sops.secrets = lib.genAttrs [
      "reverse-proxy/cloudflare_email"
      "reverse-proxy/cloudflare_api_token"
    ] (_: { owner = "poddy"; group = "poddy"; });

    networking.firewall = {
      allowedTCPPorts = [
        80
        443
        45888
      ];
    };

    home-manager.users.poddy =
      { pkgs, config, ... }:
      {
        virtualisation.quadlet =
          let
            secretsPath = nixosConfig.sops.templates."traefik-secrets".path;
            inherit (config.virtualisation.quadlet) networks pods volumes;
          in
          {
            volumes.traefik = {
              volumeConfig = { };
            };
            networks.reverse_proxy = {
              networkConfig = {
                name = "reverse_proxy";
              };
            };

            pods.reverse_proxy = {
              podConfig = {
                networks = [ networks.reverse_proxy.ref ];
                publishPorts = [
                  "80:80"
                  "443:443"
                  "8080:8080"
                  "636:636"
                  "45888:45888"
                ];
              };
            };

            containers.reverse-proxy-traefik = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStartSec = 120;
              };

              unitConfig = {
                Description = "Traefik reverse proxy container";
                After = [ pods.reverse_proxy.ref ];
              };

              containerConfig = {
                image = "docker.io/library/traefik:latest";
                pod = pods.reverse_proxy.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "traefik";
                  port = 8080;
                  subdomain = cfg.subdomain;
                  middlewares = true;
                  extraLabels = name: {
                    # Override service to use Traefik's internal dashboard API
                    "traefik.http.routers.${name}.service" = "api@internal";
                  };
                };

                # %t = XDG_RUNTIME_DIR
                volumes = [
                  "%t/podman/podman.sock:/var/run/docker.sock:ro"
                  "${volumes.traefik.ref}:/data"
                ];

                environmentFiles = [ secretsPath ];

                environments = {
                  TRAEFIK_LOG_LEVEL = "INFO";
                  TRAEFIK_PROVIDERS_DOCKER = "true";
                  TRAEFIK_PROVIDERS_DOCKER_EXPOSEDBYDEFAULT = "false";
                  TRAEFIK_API = "true";
                  TRAEFIK_API_DASHBOARD = "true";
                  TRAEFIK_API_INSECURE = "true";
                  TRAEFIK_ENTRYPOINTS_WEB_ADDRESS = ":80";
                  TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS = ":443";
                  TRAEFIK_ENTRYPOINTS_LLDAPSECURE_ADDRESS = ":636";
                  TRAEFIK_ENTRYPOINTS_SCRYPTEDHOMEKIT_ADDRESS = ":45888";
                  TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_TO = "websecure";
                  TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_SCHEME = "https";
                  TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE = "true";
                  TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE_PROVIDER = "cloudflare";
                  TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE_RESOLVERS = "1.1.1.1:53,1.0.0.1:53";
                  TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_STORAGE = "/data/acme.json";
                  TRAEFIK_SERVERSTRANSPORT_INSECURESKIPVERIFY = "true";
                }
                // lib.optionalAttrs cfg.useAcmeStaging {
                  TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_CASERVER = "https://acme-staging-v02.api.letsencrypt.org/directory";
                };

                securityLabelType = "container_runtime_t";
              };
            };
          };
      };

    sops.templates."traefik-secrets" = {
      content = ''
        TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL=${
          config.sops.placeholder."reverse-proxy/cloudflare_email"
        }
        CF_API_EMAIL=${config.sops.placeholder."reverse-proxy/cloudflare_email"}
        CF_DNS_API_TOKEN=${config.sops.placeholder."reverse-proxy/cloudflare_api_token"}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };
  };
}
