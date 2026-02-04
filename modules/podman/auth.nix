{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pods.auth;
  nixosConfig = config;
in
{
  options.services.pods.auth = {
    enable = lib.mkEnableOption "Auth pod (Authelia and LLDAP)";

    authelia = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Authelia authentication server in the auth pod";
      };
    };

    lldap = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable LLDAP directory server in the auth pod";
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
      "authelia/icloud_smtp_password" = {
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

                labels = {
                  "traefik.enable" = "true";
                  "traefik.http.routers.authelia.rule" = "Host(`auth1.nmsd.xyz`)";
                  "traefik.http.routers.authelia.entrypoints" = "websecure";
                  "traefik.http.routers.authelia.tls.certresolver" = "namecheap";
                  "traefik.http.routers.authelia.service" = "authelia";
                  "traefik.http.services.authelia.loadbalancer.server.scheme" = "http";
                  "traefik.http.services.authelia.loadbalancer.server.port" = "9091";
                  "traefik.http.middlewares.authelia.forwardauth.address" =
                    "http://host.docker.internal:9091/api/authz/forward-auth";
                  "traefik.http.middlewares.authelia.forwardauth.trustforwardheader" = "true";
                  "traefik.http.middlewares.authelia.forwardauth.authresponseheaders" =
                    "remote-user,remote-groups,remote-email,remote-name";
                };

                environments = {
                  TZ = "Europe/Amsterdam";
                  AUTHELIA_SERVER_ADDRESS = "tcp://:9091";
                  AUTHELIA_LOG_LEVEL = "debug";
                  AUTHELIA_TOTP_ISSUER = "auth1.nmsd.xyz";
                  AUTHELIA_ACCESS_CONTROL_DEFAULT_POLICY = "deny";
                  AUTHELIA_REGULATION_MAX_RETRIES = "3";
                  AUTHELIA_REGULATION_FIND_TIME = "2 minutes";
                  AUTHELIA_REGULATION_BAN_TIME = "5 minutes";
                  AUTHELIA_STORAGE_LOCAL_PATH = "/config/db.sqlite3";
                  AUTHELIA_NOTIFIER_DISABLE_STARTUP_CHECK = "false";
                  AUTHELIA_NOTIFIER_SMTP_ADDRESS = "submission://smtp.mail.me.com:587";
                  AUTHELIA_NOTIFIER_SMTP_USERNAME = "nima.saed@me.com";
                  AUTHELIA_NOTIFIER_SMTP_SENDER = "Authelia <info@nmsd.xyz>";
                  AUTHELIA_NOTIFIER_SMTP_DISABLE_REQUIRE_TLS = "false";
                  AUTHELIA_AUTHENTICATION_BACKEND_LDAP_IMPLEMENTATION = "lldap";
                  AUTHELIA_AUTHENTICATION_BACKEND_LDAP_ADDRESS = "ldaps://lldap1.nmsd.xyz:636";
                  AUTHELIA_AUTHENTICATION_BACKEND_LDAP_BASE_DN = "dc=nmsd,dc=xyz";
                  AUTHELIA_AUTHENTICATION_BACKEND_LDAP_USER = "uid=admin,ou=people,dc=nmsd,dc=xyz";
                };

                environmentFiles = [ secretsPath ];

                volumes = [ "${volumes.authelia.ref}:/config" ];
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

                labels = {
                  "traefik.enable" = "true";
                  # HTTP router for web UI
                  "traefik.http.routers.lldap.rule" = "Host(`lldap1.nmsd.xyz`)";
                  "traefik.http.routers.lldap.entrypoints" = "websecure";
                  "traefik.http.routers.lldap.tls.certresolver" = "namecheap";
                  "traefik.http.routers.lldap.service" = "lldap";
                  "traefik.http.services.lldap.loadbalancer.server.scheme" = "http";
                  "traefik.http.services.lldap.loadbalancer.server.port" = "17170";
                  #"traefik.http.routers.lldap.middlewares" = "authelia@docker";
                  # TCP router for LDAPS
                  "traefik.tcp.routers.lldap.rule" = "HostSNI(`*`)";
                  "traefik.tcp.routers.lldap.entrypoints" = "lldapsecure";
                  "traefik.tcp.routers.lldap.tls" = "true";
                  "traefik.tcp.routers.ldap.tls.domains[0].main" = "lldap1.nmsd.xyz";
                  "traefik.tcp.routers.lldap.tls.certresolver" = "namecheap";
                  "traefik.tcp.services.lldap.loadbalancer.server.port" = "3890";
                };

                environments = {
                  TZ = "Europe/Amsterdam";
                  LLDAP_LDAP_BASE_DN = "dc=nmsd,dc=xyz";
                };

                environmentFiles = [ secretsPath ];

                volumes = [ "${volumes.lldap.ref}:/data" ];
              };
            };
          };
      };

    sops.templates."auth-secrets" = {
      content = ''
        AUTHELIA_NOTIFIER_SMTP_PASSWORD=${config.sops.placeholder."authelia/icloud_smtp_password"}
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
