{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pods.auth;
  nixosConfig = config;
  inherit (config.services.pods) domain mkTraefikLabels;
  # Convert "example.com" to "dc=example,dc=com" for LDAP Base DN
  domainToBaseDN = d: lib.concatStringsSep "," (map (part: "dc=${part}") (lib.splitString "." d));
  baseDN = domainToBaseDN domain;
in
{
  imports = [
    ./container-configs/authelia.nix
    ./container-configs/lldap.nix
  ];

  options.services.pods.auth = {
    enable = lib.mkEnableOption "Auth pod (Authelia and LLDAP)";

    _baseDN = lib.mkOption {
      type = lib.types.str;
      internal = true;
      default = baseDN;
      description = "LDAP Base DN derived from domain (e.g., dc=example,dc=com)";
    };

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
    sops.secrets = lib.genAttrs [
      "authelia/smtp_password"
      "authelia/authelia_jwt_secret"
      "authelia/authelia_session_secret"
      "authelia/authelia_storage_encryption_key"
      "authelia/authelia_oidc_hmac_secret"
      "authelia/oidc_jwks_private_key"
      "authelia/oidc_jwks_certificate_chain"
      "authelia/oidc_client_secret_nextcloud"
      "authelia/oidc_client_secret_jellyfin"
      "authelia/smtp_address"
      "authelia/smtp_username"
      "ldap/lldap_ldap_user_pass"
      "ldap/lldap_key_seed"
      "ldap/lldap_jwt_secret"
    ] (_: { owner = "poddy"; group = "poddy"; });

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
                After = [ pods.auth.ref ];
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

                environments = {
                  TZ = "Europe/Amsterdam";
                  # Enable Authelia's template engine so {{ }} expressions in the
                  # config file (./config/authelia.nix) are processed at startup (reads secrets from mounted files)
                  X_AUTHELIA_CONFIG = "/etc/authelia/configuration.yml";
                  X_AUTHELIA_CONFIG_FILTERS = "template";
                };

                environmentFiles = [ secretsPath ];

                volumes = [
                  "${volumes.authelia.ref}:/config"
                  "${nixosConfig.services.pods.auth.authelia.configFile}:/etc/authelia/configuration.yml:ro"
                  "${nixosConfig.sops.secrets."authelia/oidc_jwks_private_key".path}:/secrets/oidc_jwks_key:ro"
                  "${nixosConfig.sops.secrets."authelia/oidc_jwks_certificate_chain".path}:/secrets/oidc_jwks_cert:ro"
                  "${
                    nixosConfig.sops.secrets."authelia/oidc_client_secret_nextcloud".path
                  }:/secrets/nextcloud_client_secret:ro"
                  "${
                    nixosConfig.sops.secrets."authelia/oidc_client_secret_jellyfin".path
                  }:/secrets/jellyfin_client_secret:ro"
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
                After = [ pods.auth.ref ];
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

                exec = "run --config-file /etc/lldap/lldap_config.toml";

                environments = {
                  TZ = "Europe/Amsterdam";
                  LLDAP_LDAP_BASE_DN = baseDN;
                };

                environmentFiles = [ secretsPath ];

                volumes = [
                  "${volumes.lldap.ref}:/data"
                  "${nixosConfig.services.pods.auth.lldap.configFile}:/etc/lldap/lldap_config.toml:ro"
                ];
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
