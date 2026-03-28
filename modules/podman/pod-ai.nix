{
  config,
  lib,
  ...
}:

let
  cfg = config.services.pods.ai;
  nixosConfig = config;
  inherit (config.services.pods) mkTraefikLabels domain;
  authCfg = config.services.pods.auth;
in
{
  options.services.pods.ai = {
    enable = lib.mkEnableOption "AI pod";

    litellm = {
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "litellm";
        description = "Subdomain for LiteLLM proxy";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.pods._enabledPods = [ "ai" ];

    assertions = [
      {
        assertion = builtins.elem "reverse-proxy" config.services.pods._enabledPods;
        message = "services.pods.ai requires Traefik (reverse-proxy) to be configured";
      }
    ];

    sops.secrets = lib.genAttrs [
      "ai/litellm/master_key"
      "ai/litellm/db_password"
      "ai/litellm/oidc_client_secret_litellm"
    ] (_: { owner = "poddy"; group = "poddy"; });

    sops.templates."ai-litellm-db-env" = {
      content = ''
        POSTGRES_PASSWORD=${config.sops.placeholder."ai/litellm/db_password"}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };

    sops.templates."ai-litellm-env" = {
      content = ''
        LITELLM_MASTER_KEY=${config.sops.placeholder."ai/litellm/master_key"}
        DATABASE_URL=postgresql://llmproxy:${config.sops.placeholder."ai/litellm/db_password"}@127.0.0.1:5432/litellm
        STORE_MODEL_IN_DB=True
        GENERIC_CLIENT_ID=litellm
        GENERIC_CLIENT_SECRET=${config.sops.placeholder."ai/litellm/oidc_client_secret_litellm"}
        GENERIC_AUTHORIZATION_ENDPOINT=https://${authCfg.authelia.subdomain}.${domain}/api/oidc/authorization
        GENERIC_TOKEN_ENDPOINT=https://${authCfg.authelia.subdomain}.${domain}/api/oidc/token
        GENERIC_USERINFO_ENDPOINT=https://${authCfg.authelia.subdomain}.${domain}/api/oidc/userinfo
        PROXY_BASE_URL=https://litellm.${domain}
        GENERIC_SCOPE=openid profile email litellm_scope
        GENERIC_USER_ROLE_ATTRIBUTE=litellm_role
        AUTO_REDIRECT_UI_LOGIN_TO_SSO=true
        PROXY_LOGOUT_URL=https://${authCfg.authelia.subdomain}.${domain}/logout
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
            volumes.ai_litellm_db = {
              volumeConfig = { };
            };

            pods.ai = {
              podConfig = {
                networks = [ networks.reverse_proxy.ref ];
              };
            };

            containers.ai-litellm-db = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "LiteLLM PostgreSQL database container";
                After = [ pods.ai.ref ];
              };

              containerConfig = {
                image = "docker.io/postgres:16-alpine";
                pod = pods.ai.ref;
                autoUpdate = "registry";

                environments = {
                  POSTGRES_USER = "llmproxy";
                  POSTGRES_DB = "litellm";
                };

                environmentFiles = [ nixosConfig.sops.templates."ai-litellm-db-env".path ];

                volumes = [
                  "${volumes.ai_litellm_db.ref}:/var/lib/postgresql/data"
                ];

                healthCmd = "pg_isready -d litellm -U llmproxy";
              };
            };

            containers.ai-litellm = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "LiteLLM proxy container";
                After = [
                  pods.ai.ref
                  "ai-litellm-db.service"
                ];
              };

              containerConfig = {
                image = "docker.litellm.ai/berriai/litellm-database:main-stable";
                pod = pods.ai.ref;
                autoUpdate = "registry";

                environmentFiles = [ nixosConfig.sops.templates."ai-litellm-env".path ];

                healthCmd = "python3 -c 'import urllib.request; urllib.request.urlopen(\"http://localhost:4000/health/liveliness\")'";


                labels = mkTraefikLabels {
                  name = "litellm";
                  port = 4000;
                  subdomain = cfg.litellm.subdomain;
                  middlewares = false;
                };
              };
            };
          };
      };
  };
}
