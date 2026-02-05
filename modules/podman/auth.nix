{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pods.auth;
  nixosConfig = config;
  # Alternative: inherit (config.services.pods) domain mkTraefikLabels;
  domain = config.services.pods.domain;
  mkTraefikLabels = config.services.pods.mkTraefikLabels;
  # Convert "example.com" to "dc=example,dc=com" for LDAP Base DN
  domainToBaseDN = d: lib.concatStringsSep "," (map (part: "dc=${part}") (lib.splitString "." d));
  baseDN = domainToBaseDN domain;
in
{
  imports = [ ./configs/authelia.nix ];

  options.services.pods.auth = {
    enable = lib.mkEnableOption "Auth pod (Authelia and LLDAP)";

    authelia = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Authelia authentication server in the auth pod";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "authelia";
        description = "Subdomain for Authelia authentication server";
      };
    };

    lldap = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable LLDAP directory server in the auth pod";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "lldap";
        description = "Subdomain for LLDAP directory server";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.pods._enabledPods = [ "auth" ];

    assertions = [
      {
        assertion = config.services.pods.reverse-proxy.enable;
        message = "services.pods.auth requires services.pods.reverse-proxy to be enabled (for the reverse_proxy network)";
      }
    ];

    # Declare secrets this module needs
    sops.secrets = {
      "authelia/smtp_password" = {
        owner = "poddy";
        group = "poddy";
      };
      "authelia/authelia_jwt_secret" = {
        owner = "poddy";
        group = "poddy";
      };
      "authelia/authelia_session_secret" = {
        owner = "poddy";
        group = "poddy";
      };
      "authelia/authelia_storage_encryption_key" = {
        owner = "poddy";
        group = "poddy";
      };
      "authelia/authelia_oidc_hmac_secret" = {
        owner = "poddy";
        group = "poddy";
      };
      "authelia/oidc_jwks_private_key" = {
        owner = "poddy";
        group = "poddy";
      };
      "authelia/oidc_jwks_certificate_chain" = {
        owner = "poddy";
        group = "poddy";
      };
      "authelia/oidc_client_secret_nextcloud" = {
        owner = "poddy";
        group = "poddy";
      };
      "authelia/oidc_client_secret_jellyfin" = {
        owner = "poddy";
        group = "poddy";
      };
      "authelia/smtp_address" = {
        owner = "poddy";
        group = "poddy";
      };
      "authelia/smtp_username" = {
        owner = "poddy";
        group = "poddy";
      };
      "ldap/lldap_ldap_user_pass" = {
        owner = "poddy";
        group = "poddy";
      };
      "ldap/lldap_key_seed" = {
        owner = "poddy";
        group = "poddy";
      };
      "ldap/lldap_jwt_secret" = {
        owner = "poddy";
        group = "poddy";
      };
    };

    home-manager.users.poddy =
      { pkgs, config, ... }:
      {
        virtualisation.quadlet =
          let
            secretsPath = nixosConfig.sops.templates."auth-secrets".path;
            inherit (config.virtualisation.quadlet) networks pods volumes;
          in
          {
            volumes.authelia = {
              volumeConfig = { };
            };
            volumes.lldap = {
              volumeConfig = { };
            };

            pods.auth = {
              podConfig = {
                networks = [ networks.reverse_proxy.ref ];
                publishPorts = [ "9091:9091" ];
              };
            };

            containers.authelia = lib.mkIf cfg.authelia.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Authelia authentication server container";
                After = [ "auth-pod.service" ];
              };

              containerConfig = {
                image = "ghcr.io/authelia/authelia:latest";
                pod = pods.auth.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "authelia";
                  port = 9091;
                  subdomain = cfg.authelia.subdomain;
                  extraLabels = _: {
                    # ForwardAuth middleware definition (used by other services via middlewares = true)
                    # Note: middleware name stays "authelia" regardless of container name
                    "traefik.http.middlewares.authelia.forwardauth.address" =
                      "http://host.docker.internal:9091/api/authz/forward-auth";
                    "traefik.http.middlewares.authelia.forwardauth.trustforwardheader" = "true";
                    "traefik.http.middlewares.authelia.forwardauth.authresponseheaders" =
                      "remote-user,remote-groups,remote-email,remote-name";
                  };
                };

                # All non-secret config is in the generated configuration.yml (configs/authelia.nix).
                # Only TZ (Docker-level) and JWKS references remain as env vars.
                environments = {
                  TZ = "Europe/Amsterdam";
                  # JWKS key/cert are multiline PEM — mounted as sops secret files
                  AUTHELIA_IDENTITY_PROVIDERS_OIDC_JWKS_0_KEY_ID = "authelia_key";
                  AUTHELIA_IDENTITY_PROVIDERS_OIDC_JWKS_0_KEY_FILE = "/secrets/oidc_jwks_key";
                  AUTHELIA_IDENTITY_PROVIDERS_OIDC_JWKS_0_CERTIFICATE_CHAIN_FILE = "/secrets/oidc_jwks_cert";
                };

                environmentFiles = [ secretsPath ];

                volumes = [
                  "${volumes.authelia.ref}:/config"
                  "${nixosConfig.services.pods.auth.authelia.configFile}:/config/configuration.yml:ro"
                  "${nixosConfig.sops.secrets."authelia/oidc_jwks_private_key".path}:/secrets/oidc_jwks_key:ro"
                  "${nixosConfig.sops.secrets."authelia/oidc_jwks_certificate_chain".path}:/secrets/oidc_jwks_cert:ro"
                ];
              };
            };

            containers.lldap = lib.mkIf cfg.lldap.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "LLDAP directory server container";
                After = [ "auth-pod.service" ];
              };

              containerConfig = {
                image = "docker.io/lldap/lldap:stable";
                pod = pods.auth.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "lldap";
                  port = 17170;
                  subdomain = cfg.lldap.subdomain;
                  # middlewares = true;  # Uncomment to enable Authelia protection
                  extraLabels = name: {
                    # TCP router for LDAPS
                    "traefik.tcp.routers.${name}.rule" = "HostSNI(`*`)";
                    "traefik.tcp.routers.${name}.entrypoints" = "lldapsecure";
                    "traefik.tcp.routers.${name}.tls" = "true";
                    "traefik.tcp.routers.${name}.tls.domains[0].main" = "${cfg.lldap.subdomain}.${domain}";
                    "traefik.tcp.routers.${name}.tls.certresolver" = "namecheap";
                    "traefik.tcp.services.${name}.loadbalancer.server.port" = "3890";
                  };
                };

                environments = {
                  TZ = "Europe/Amsterdam";
                  LLDAP_LDAP_BASE_DN = baseDN;
                };

                environmentFiles = [ secretsPath ];

                volumes = [ "${volumes.lldap.ref}:/data" ];
              };
            };
          };
      };

    sops.templates."auth-secrets" = {
      content = ''
        AUTHELIA_NOTIFIER_SMTP_PASSWORD=${config.sops.placeholder."authelia/smtp_password"}
        AUTHELIA_NOTIFIER_SMTP_ADDRESS=${config.sops.placeholder."authelia/smtp_address"}
        AUTHELIA_NOTIFIER_SMTP_USERNAME=${config.sops.placeholder."authelia/smtp_username"}
        AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET=${
          config.sops.placeholder."authelia/authelia_jwt_secret"
        }
        AUTHELIA_SESSION_SECRET=${config.sops.placeholder."authelia/authelia_session_secret"}
        AUTHELIA_STORAGE_ENCRYPTION_KEY=${
          config.sops.placeholder."authelia/authelia_storage_encryption_key"
        }
        AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET=${
          config.sops.placeholder."authelia/authelia_oidc_hmac_secret"
        }
        AUTHELIA_IDENTITY_PROVIDERS_OIDC_CLIENTS_0_CLIENT_SECRET=${
          config.sops.placeholder."authelia/oidc_client_secret_nextcloud"
        }
        AUTHELIA_IDENTITY_PROVIDERS_OIDC_CLIENTS_1_CLIENT_SECRET=${
          config.sops.placeholder."authelia/oidc_client_secret_jellyfin"
        }
        AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD=${config.sops.placeholder."ldap/lldap_ldap_user_pass"}
        LLDAP_LDAP_USER_PASS=${config.sops.placeholder."ldap/lldap_ldap_user_pass"}
        LLDAP_KEY_SEED=${config.sops.placeholder."ldap/lldap_key_seed"}
        LLDAP_JWT_SECRET=${config.sops.placeholder."ldap/lldap_jwt_secret"}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };
  };
}
