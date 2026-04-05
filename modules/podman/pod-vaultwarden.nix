{
  config,
  lib,
  ...
}:

let
  cfg = config.services.pods.vaultwarden;
  nixosConfig = config;
  inherit (config.services.pods) mkTraefikLabels domain;
  authCfg = config.services.pods.auth;
in
{
  options.services.pods.vaultwarden = {
    enable = lib.mkEnableOption "Vaultwarden password manager pod";

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "vault";
      description = "Subdomain for Vaultwarden (e.g., vault -> vault.example.com)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.pods._enabledPods = [ "vaultwarden" ];

    assertions = [
      {
        assertion = builtins.elem "reverse-proxy" config.services.pods._enabledPods;
        message = "services.pods.vaultwarden requires Traefik (reverse-proxy) to be configured";
      }
      {
        assertion = builtins.elem "auth" config.services.pods._enabledPods;
        message = "services.pods.vaultwarden requires Authelia (auth) for OIDC authentication";
      }
    ];

    sops.secrets =
      lib.genAttrs
        [
          "vaultwarden/db_password"
          "vaultwarden/admin_token"
          "vaultwarden/oidc_client_secret"
        ]
        (_: {
          owner = "poddy";
          group = "poddy";
        });

    sops.templates."vaultwarden-db-env" = {
      content = ''
        POSTGRES_PASSWORD=${config.sops.placeholder."vaultwarden/db_password"}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };

    sops.templates."vaultwarden-app-env" = {
      content = ''
        DATABASE_URL=postgresql://vaultwarden:${
          config.sops.placeholder."vaultwarden/db_password"
        }@127.0.0.1/vaultwarden
        ADMIN_TOKEN=${config.sops.placeholder."vaultwarden/admin_token"}
        SSO_CLIENT_SECRET=${config.sops.placeholder."vaultwarden/oidc_client_secret"}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };

    home-manager.users.poddy =
      { config, ... }:
      {
        virtualisation.quadlet =
          let
            inherit (config.virtualisation.quadlet) networks pods volumes;
          in
          {
            volumes.vaultwarden_db = {
              volumeConfig = { };
            };

            volumes.vaultwarden_data = {
              volumeConfig = { };
            };

            pods.vaultwarden = {
              podConfig = {
                networks = [ networks.reverse_proxy.ref ];
              };
            };

            containers.vaultwarden-db = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Vaultwarden PostgreSQL database container";
                After = [ pods.vaultwarden.ref ];
              };

              containerConfig = {
                image = "docker.io/postgres:16-alpine";
                pod = pods.vaultwarden.ref;
                autoUpdate = "registry";

                environments = {
                  POSTGRES_USER = "vaultwarden";
                  POSTGRES_DB = "vaultwarden";
                };

                environmentFiles = [ nixosConfig.sops.templates."vaultwarden-db-env".path ];

                volumes = [
                  "${volumes.vaultwarden_db.ref}:/var/lib/postgresql/data"
                ];

                healthCmd = "pg_isready -d vaultwarden -U vaultwarden";
              };
            };

            containers.vaultwarden-app = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Vaultwarden password manager container";
                After = [
                  pods.vaultwarden.ref
                  "vaultwarden-db.service"
                ];
              };

              containerConfig = {
                # SSO support included in stable releases since v1.35.0 (Dec 2024)
                image = "docker.io/vaultwarden/server:latest";
                pod = pods.vaultwarden.ref;
                autoUpdate = "registry";

                environments = {
                  DOMAIN = "https://${cfg.subdomain}.${domain}";
                  # SSO_ONLY disables email+password login; users must authenticate via Authelia.
                  # Master password is still required to decrypt the vault (zero-knowledge encryption).
                  SSO_ENABLED = "true";
                  SSO_ONLY = "true";
                  SSO_CLIENT_ID = "vaultwarden";
                  SSO_AUTHORITY = "https://${authCfg.authelia.subdomain}.${domain}";
                  SSO_PKCE = "true";
                };

                environmentFiles = [ nixosConfig.sops.templates."vaultwarden-app-env".path ];

                volumes = [
                  "${volumes.vaultwarden_data.ref}:/data"
                ];

                labels = mkTraefikLabels {
                  name = "vaultwarden";
                  port = 80;
                  subdomain = cfg.subdomain;
                  # No ForwardAuth middleware — Vaultwarden handles auth itself via OIDC
                  middlewares = false;
                };
              };
            };
          };
      };
  };
}

# Post-deployment notes:
#
# 1. Wait for containers to start:
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman logs vaultwarden-db
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman logs vaultwarden-app
#
# 2. Visit https://vault.<domain> — login page shows "Enterprise SSO" only (no email/password form).
#    First-time users: click "Enterprise SSO" → Authelia 2FA → set master password on first login.
#
# 3. Admin panel: https://vault.<domain>/admin (use raw ADMIN_TOKEN value, not the argon2 hash).
#
# 4. Before deployment, add these secrets to sops:
#    - vaultwarden/db_password           (strong random password)
#    - vaultwarden/admin_token           (strong random token)
#    - vaultwarden/oidc_client_secret    (raw secret value)
#    - authelia/oidc_client_secret_vaultwarden  (argon2 hash of the same raw secret)
#      Generate hash: authelia crypto hash generate argon2 --password 'your-raw-secret'
