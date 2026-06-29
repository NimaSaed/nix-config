{
  config,
  lib,
  ...
}:

let
  cfg = config.services.pods.paperless;
  nixosConfig = config;
  inherit (config.services.pods) domain mkTraefikLabels;
  authCfg = config.services.pods.auth;
  authBaseUrl = "https://${authCfg.authelia.subdomain}.${domain}";
  litellmUrl = "http://ai:4000/v1";
  helpersEnabled = cfg.ai.enable || cfg.gpt.enable;
in
{
  options.services.pods.paperless = {
    enable = lib.mkEnableOption "Paperless-ngx document management pod";

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "paperless";
      description = "Subdomain for Paperless-ngx (e.g., paperless -> paperless.example.com)";
    };

    consumeDir = lib.mkOption {
      type = lib.types.path;
      default = "/data/scans";
      description = ''
        Host directory Paperless watches for incoming documents. Defaults to the
        Samba scan share so the network scanner drops files here. Must be group
        poddy with the setgid bit (see hosts/chestnut/samba.nix).
      '';
    };

    ocrLanguage = lib.mkOption {
      type = lib.types.str;
      default = "eng";
      description = "Tesseract OCR language(s), e.g. \"eng\" or \"eng+nld\".";
    };

    ocrLanguages = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "nld";
      description = "Extra Tesseract language packs to install at container start (space separated).";
    };

    llmModel = lib.mkOption {
      type = lib.types.str;
      default = "openai/gpt-5.4-nano";
      description = "LiteLLM model alias used by the paperless-ai / paperless-gpt helpers.";
    };

    ai = {
      enable = lib.mkEnableOption "paperless-ai helper (auto title/tag analysis + RAG chat) via LiteLLM";
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "paperless-ai";
        description = "Subdomain for paperless-ai";
      };
    };

    gpt = {
      enable = lib.mkEnableOption "paperless-gpt helper (LLM tag/title generation) via LiteLLM";
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "paperless-gpt";
        description = "Subdomain for paperless-gpt";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.pods._enabledPods = [ "paperless" ];

    assertions = [
      {
        assertion = builtins.elem "reverse-proxy" config.services.pods._enabledPods;
        message = "services.pods.paperless requires Traefik (reverse-proxy) to be configured";
      }
      {
        assertion = builtins.elem "auth" config.services.pods._enabledPods;
        message = "services.pods.paperless requires Authelia (auth) for OIDC authentication";
      }
      {
        assertion = !helpersEnabled || builtins.elem "ai" config.services.pods._enabledPods;
        message = "services.pods.paperless.{ai,gpt} require the ai pod (LiteLLM) to be enabled";
      }
    ];

    sops.secrets =
      lib.genAttrs
        [
          "paperless/db_password"
          "paperless/secret_key"
          "paperless/admin_password"
          "paperless/oidc_client_secret"
        ]
        (_: {
          owner = "poddy";
          group = "poddy";
        })
      // lib.optionalAttrs helpersEnabled {
        "paperless/api_token" = {
          owner = "poddy";
          group = "poddy";
        };
      };

    sops.templates."paperless-db-env" = {
      content = ''
        POSTGRES_PASSWORD=${config.sops.placeholder."paperless/db_password"}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };

    # SOCIALACCOUNT_PROVIDERS embeds the OIDC client secret, so the whole blob lives in
    # the sops template (single line — podman env-file is literal). server_url is the
    # base issuer URL; allauth appends /.well-known/openid-configuration itself.
    sops.templates."paperless-env" = {
      content = ''
        PAPERLESS_DBPASS=${config.sops.placeholder."paperless/db_password"}
        PAPERLESS_SECRET_KEY=${config.sops.placeholder."paperless/secret_key"}
        PAPERLESS_ADMIN_PASSWORD=${config.sops.placeholder."paperless/admin_password"}
        PAPERLESS_SOCIALACCOUNT_PROVIDERS={"openid_connect":{"OAUTH_PKCE_ENABLED":true,"APPS":[{"provider_id":"authelia","name":"Authelia","client_id":"paperless","secret":"${
          config.sops.placeholder."paperless/oidc_client_secret"
        }","settings":{"server_url":"${authBaseUrl}","token_auth_method":"client_secret_basic"}}],"SCOPE":["openid","profile","email","groups"]}}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };

    sops.templates."paperless-ai-env" = lib.mkIf cfg.ai.enable {
      content = ''
        CUSTOM_API_KEY=${config.sops.placeholder."ai/openwebui/litellm_api_key"}
        PAPERLESS_API_TOKEN=${config.sops.placeholder."paperless/api_token"}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };

    sops.templates."paperless-gpt-env" = lib.mkIf cfg.gpt.enable {
      content = ''
        OPENAI_API_KEY=${config.sops.placeholder."ai/openwebui/litellm_api_key"}
        PAPERLESS_API_TOKEN=${config.sops.placeholder."paperless/api_token"}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };

    home-manager.users.poddy =
      { config, pkgs, ... }:
      {
        # Seed a fixed DRF API token (from sops) into Paperless so the helpers can
        # authenticate without a manual GUI token. Retries until the admin user exists.
        systemd.user.services.paperless-token-seed = lib.mkIf helpersEnabled {
          Unit = {
            Description = "Seed Paperless API token for AI helpers";
            After = [ "paperless-web.service" ];
            Wants = [ "paperless-web.service" ];
          };
          Service = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "paperless-token-seed" ''
              set -euo pipefail
              TOKEN=$(cat ${nixosConfig.sops.secrets."paperless/api_token".path})
              for _ in $(seq 1 60); do
                CID=$(${pkgs.podman}/bin/podman ps --format '{{.Names}}' \
                  | ${pkgs.gnugrep}/bin/grep -E 'paperless-web' | head -n1 || true)
                if [ -n "$CID" ] && ${pkgs.podman}/bin/podman exec -e SEED_TOKEN="$TOKEN" "$CID" \
                  python3 manage.py shell -c '
              import os
              from django.contrib.auth import get_user_model
              from rest_framework.authtoken.models import Token
              u = get_user_model().objects.get(username="admin")
              Token.objects.filter(user=u).delete()
              Token.objects.create(user=u, key=os.environ["SEED_TOKEN"])
              '; then
                  echo "paperless API token seeded"
                  exit 0
                fi
                sleep 10
              done
              echo "paperless-token-seed: timed out waiting for admin user" >&2
              exit 1
            '';
          };
          Install.WantedBy = [ "default.target" ];
        };

        virtualisation.quadlet =
          let
            inherit (config.virtualisation.quadlet) networks pods volumes;
          in
          {
            volumes.paperless_db = {
              volumeConfig = { };
            };
            volumes.paperless_broker = {
              volumeConfig = { };
            };
            volumes.paperless_data = {
              volumeConfig = { };
            };
            volumes.paperless_media = {
              volumeConfig = { };
            };
            volumes.paperless_export = {
              volumeConfig = { };
            };
            volumes.paperless_ai_data = lib.mkIf cfg.ai.enable {
              volumeConfig = { };
            };
            volumes.paperless_gpt_prompts = lib.mkIf cfg.gpt.enable {
              volumeConfig = { };
            };

            pods.paperless = {
              podConfig = {
                networks = [ networks.reverse_proxy.ref ];
              };
            };

            pods.paperless-llm = lib.mkIf helpersEnabled {
              podConfig = {
                networks = [ networks.reverse_proxy.ref ];
              };
            };

            containers.paperless-db = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Paperless-ngx PostgreSQL database container";
                After = [ pods.paperless.ref ];
              };

              containerConfig = {
                image = "docker.io/postgres:18-alpine";
                pod = pods.paperless.ref;
                autoUpdate = "registry";

                environments = {
                  POSTGRES_USER = "paperless";
                  POSTGRES_DB = "paperless";
                };

                environmentFiles = [ nixosConfig.sops.templates."paperless-db-env".path ];

                # pg18 moved PGDATA under /var/lib/postgresql/<ver>/docker, so the
                # volume is mounted at the parent dir (matches paperless-ngx's compose).
                volumes = [
                  "${volumes.paperless_db.ref}:/var/lib/postgresql"
                ];

                healthCmd = "pg_isready -d paperless -U paperless";
              };
            };

            containers.paperless-broker = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Paperless-ngx Valkey broker container";
                After = [ pods.paperless.ref ];
              };

              containerConfig = {
                image = "docker.io/valkey/valkey:9";
                pod = pods.paperless.ref;
                autoUpdate = "registry";

                # Persist the broker (matches upstream's redisdata volume) so queued
                # and scheduled Celery tasks survive a restart.
                exec = [
                  "valkey-server"
                  "--bind"
                  "127.0.0.1"
                  "--port"
                  "6379"
                  "--appendonly"
                  "yes"
                  "--loglevel"
                  "warning"
                ];

                volumes = [
                  "${volumes.paperless_broker.ref}:/data:U"
                ];
              };
            };

            containers.paperless-gotenberg = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Paperless-ngx Gotenberg (Office to PDF) container";
                After = [ pods.paperless.ref ];
              };

              containerConfig = {
                image = "docker.io/gotenberg/gotenberg:8";
                pod = pods.paperless.ref;
                autoUpdate = "registry";

                exec = [
                  "gotenberg"
                  "--chromium-disable-javascript=true"
                  "--chromium-allow-list=file:///tmp/.*"
                ];
              };
            };

            containers.paperless-tika = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Paperless-ngx Apache Tika (document parsing) container";
                After = [ pods.paperless.ref ];
              };

              containerConfig = {
                image = "docker.io/apache/tika:latest";
                pod = pods.paperless.ref;
                autoUpdate = "registry";
              };
            };

            containers.paperless-web = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStartSec = 300;
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Paperless-ngx web application container";
                After = [
                  pods.paperless.ref
                  "paperless-db.service"
                  "paperless-broker.service"
                  "paperless-gotenberg.service"
                  "paperless-tika.service"
                ];
              };

              containerConfig = {
                image = "ghcr.io/paperless-ngx/paperless-ngx:latest";
                pod = pods.paperless.ref;
                autoUpdate = "registry";

                environmentFiles = [ nixosConfig.sops.templates."paperless-env".path ];

                environments = {
                  PAPERLESS_TIME_ZONE = "Europe/Amsterdam";
                  PAPERLESS_URL = "https://${cfg.subdomain}.${domain}";

                  PAPERLESS_DBENGINE = "postgresql";
                  PAPERLESS_DBHOST = "127.0.0.1";
                  PAPERLESS_DBPORT = "5432";
                  PAPERLESS_DBNAME = "paperless";
                  PAPERLESS_DBUSER = "paperless";

                  PAPERLESS_REDIS = "redis://127.0.0.1:6379";

                  PAPERLESS_TIKA_ENABLED = "1";
                  PAPERLESS_TIKA_ENDPOINT = "http://127.0.0.1:9998";
                  PAPERLESS_TIKA_GOTENBERG_ENDPOINT = "http://127.0.0.1:3000";

                  # Scanner writes over SMB; poll so files are picked up reliably.
                  PAPERLESS_CONSUMER_POLLING = "30";
                  PAPERLESS_CONSUMER_RECURSIVE = "true";

                  PAPERLESS_OCR_LANGUAGE = cfg.ocrLanguage;
                  PAPERLESS_OCR_LANGUAGES = cfg.ocrLanguages;

                  PAPERLESS_ADMIN_USER = "admin";

                  # OIDC via Authelia (django-allauth). Group gating is enforced by
                  # Authelia's paperless_access policy; new SSO users auto-provision.
                  PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
                  PAPERLESS_SOCIAL_AUTO_SIGNUP = "true";
                  PAPERLESS_ACCOUNT_ALLOW_SIGNUPS = "false";
                  PAPERLESS_REDIRECT_LOGIN_TO_SSO = "true";
                };

                volumes = [
                  "${volumes.paperless_data.ref}:/usr/src/paperless/data"
                  "${volumes.paperless_media.ref}:/usr/src/paperless/media"
                  "${volumes.paperless_export.ref}:/usr/src/paperless/export"
                  "${cfg.consumeDir}:/usr/src/paperless/consume:rw"
                ];

                healthCmd = "curl -fs http://localhost:8000 || exit 1";

                labels = mkTraefikLabels {
                  name = "paperless";
                  port = 8000;
                  subdomain = cfg.subdomain;
                  # Paperless handles auth itself via OIDC — no forward-auth middleware.
                  middlewares = false;
                };
              };
            };

            containers.paperless-ai = lib.mkIf cfg.ai.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "paperless-ai (LLM document analysis + RAG) container";
                After = [ pods.paperless-llm.ref ];
              };

              containerConfig = {
                image = "docker.io/clusterzx/paperless-ai:latest";
                pod = pods.paperless-llm.ref;
                autoUpdate = "registry";

                environmentFiles = [ nixosConfig.sops.templates."paperless-ai-env".path ];

                environments = {
                  PUID = "1000";
                  PGID = "1000";
                  PAPERLESS_AI_PORT = "3000";
                  PAPERLESS_AI_INITIAL_SETUP = "yes";
                  PAPERLESS_API_URL = "http://paperless:8000/api";
                  PAPERLESS_USERNAME = "admin";
                  AI_PROVIDER = "custom";
                  CUSTOM_BASE_URL = litellmUrl;
                  CUSTOM_MODEL = cfg.llmModel;
                  RAG_SERVICE_ENABLED = "true";
                  RAG_SERVICE_URL = "http://localhost:8000";
                };

                volumes = [
                  "${volumes.paperless_ai_data.ref}:/app/data:U"
                ];

                labels = mkTraefikLabels {
                  name = "paperless-ai";
                  port = 3000;
                  subdomain = cfg.ai.subdomain;
                  middlewares = true;
                };
              };
            };

            containers.paperless-gpt = lib.mkIf cfg.gpt.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "paperless-gpt (LLM tag/title generation) container";
                After = [ pods.paperless-llm.ref ];
              };

              containerConfig = {
                image = "ghcr.io/icereed/paperless-gpt:latest";
                pod = pods.paperless-llm.ref;
                autoUpdate = "registry";

                environmentFiles = [ nixosConfig.sops.templates."paperless-gpt-env".path ];

                environments = {
                  PAPERLESS_BASE_URL = "http://paperless:8000";
                  LLM_PROVIDER = "openai";
                  LLM_MODEL = cfg.llmModel;
                  OPENAI_BASE_URL = litellmUrl;
                  LLM_LANGUAGE = "Dutch";
                };

                volumes = [
                  "${volumes.paperless_gpt_prompts.ref}:/app/prompts"
                ];

                labels = mkTraefikLabels {
                  name = "paperless-gpt";
                  port = 8080;
                  subdomain = cfg.gpt.subdomain;
                  middlewares = true;
                };
              };
            };
          };
      };
  };
}

# Post-deployment notes (run AFTER first boot):
#
# 1. In LLDAP, create groups: paperless-users (and optionally paperless-admins),
#    then add the relevant users so Authelia's paperless_access policy lets them in.
#
# 2. First admin login: the superuser "admin" is created from
#    paperless/admin_password. Use it to mark SSO-provisioned users as staff/admin
#    under Settings -> Users & Groups if they need more than default permissions.
#
# 3. Verify the consume pipeline:
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman logs paperless-web
#    Drop a PDF into /data/scans (or scan from the MFC-L8390CDW) -> it should be
#    imported and then removed from the consume dir.
#
# 4. Helpers (phase 2): paperless-ai RAG needs an embedding model configured in
#    LiteLLM; if a doc is tagged "paperless-gpt"/"paperless-gpt-auto" and paperless-gpt
#    did not auto-create those tags, create them once in Paperless.
