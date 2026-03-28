{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pods.nextcloud;
  authCfg = config.services.pods.auth;
  nixosConfig = config;
  inherit (config.services.pods) domain mkTraefikLabels;
in
{
  imports = [
    ./container-configs/nextcloud.nix
    ./container-configs/nextcloud-mariadb.nix
    ./container-configs/nextcloud-nginx.nix
  ];

  options.services.pods.nextcloud = {
    enable = lib.mkEnableOption "Nextcloud pod (cloud storage and collaboration platform)";

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "cloud";
      description = "Subdomain for Nextcloud (e.g., cloud -> cloud.nmsd.xyz)";
    };

    collabora = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Collabora Office for online document editing";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "office";
        description = "Subdomain for Collabora CODE";
      };
    };

    whiteboard = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Nextcloud Whiteboard real-time collaboration server";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "whiteboard";
        description = "Subdomain for the Whiteboard WebSocket server";
      };
    };

    adminUser = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "Initial Nextcloud admin username";
    };

    phoneRegion = lib.mkOption {
      type = lib.types.str;
      default = "NL";
      description = "Default phone region code for phone number validation";
    };
  };

  config = lib.mkIf cfg.enable {
    services.pods._enabledPods = [ "nextcloud" ];

    assertions = [
      {
        assertion = builtins.elem "reverse-proxy" config.services.pods._enabledPods;
        message = "services.pods.nextcloud requires Traefik (reverse-proxy) to be configured";
      }
      {
        assertion = builtins.elem "auth" config.services.pods._enabledPods;
        message = "services.pods.nextcloud requires Authelia (auth) for OIDC authentication";
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
            # Named volumes for persistent data
            volumes.nextcloud_data = {
              volumeConfig = { };
            };
            volumes.nextcloud_db = {
              volumeConfig = { };
            };
            volumes.nextcloud_redis = {
              volumeConfig = { };
            };

            # Pod definition
            pods.nextcloud = {
              podConfig = {
                networks = [ networks.reverse_proxy.ref ];
                #userns = "keep-id:uid=1001,gid=998";
              };
            };

            # Container 1: MariaDB LTS database
            containers.nextcloud-db = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Nextcloud MariaDB database container";
                After = [ pods.nextcloud.ref ];
              };

              containerConfig = {
                image = "docker.io/library/mariadb:11.4";
                pod = pods.nextcloud.ref;
                autoUpdate = "registry";

                environments = {
                  TZ = "Europe/Amsterdam";
                  MYSQL_DATABASE = "nextcloud";
                  MYSQL_USER = "nextcloud";
                };

                environmentFiles = [ nixosConfig.sops.templates."nextcloud-db-secrets".path ];

                volumes = [
                  "${volumes.nextcloud_db.ref}:/var/lib/mysql:U"
                  "${nixosConfig.services.pods.nextcloud._mariadbConfigFile}:/etc/mysql/conf.d/nextcloud.cnf:ro"
                ];
              };
            };

            # Container 2: Redis 8.0 cache
            containers.nextcloud-redis = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Nextcloud Redis cache container";
                After = [ pods.nextcloud.ref ];
              };

              containerConfig = {
                image = "docker.io/library/redis:8.0-alpine";
                pod = pods.nextcloud.ref;
                autoUpdate = "registry";

                exec = "redis-server /etc/redis/redis.conf";

                volumes = [
                  "${volumes.nextcloud_redis.ref}:/data:U"
                  "${nixosConfig.sops.templates."redis.conf".path}:/etc/redis/redis.conf:ro"
                ];
              };
            };

            # Container 3: Nextcloud 33 PHP-FPM backend
            containers.nextcloud-app = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Nextcloud PHP-FPM backend container";
                After = [
                  pods.nextcloud.ref
                  "nextcloud-db.service"
                  "nextcloud-redis.service"
                ];
              };

              containerConfig = {
                image = "docker.io/library/nextcloud:33.0-fpm";
                pod = pods.nextcloud.ref;
                autoUpdate = "registry";
                user = "1001:998";

                environments = {
                  TZ = "Europe/Amsterdam";

                  # Database connection (pod-local via 127.0.0.1)
                  MYSQL_HOST = "127.0.0.1";
                  MYSQL_DATABASE = "nextcloud";
                  MYSQL_USER = "nextcloud";

                  # Trusted domain and protocol (behind Traefik HTTPS reverse proxy)
                  NEXTCLOUD_TRUSTED_DOMAINS = "${cfg.subdomain}.${domain}";
                  OVERWRITEPROTOCOL = "https";
                  OVERWRITEHOST = "${cfg.subdomain}.${domain}";
                  OVERWRITECLIURL = "https://${cfg.subdomain}.${domain}";

                  # PHP tuning
                  PHP_MEMORY_LIMIT = "2G";
                  PHP_UPLOAD_LIMIT = "10G";
                };

                environmentFiles = [ nixosConfig.sops.templates."nextcloud-app-secrets".path ];

                volumes = [
                  "${volumes.nextcloud_data.ref}:/var/www/html:U"
                  "${nixosConfig.services.pods.nextcloud._configFile}:/var/www/html/config/zzz-nix-overrides.config.php:ro"
                  "${nixosConfig.services.pods.nextcloud._fpmPoolFile}:/usr/local/etc/php-fpm.d/zzz-nix-fpm-pool.conf:ro"
                ];
              };
            };

            # Container 4: Nginx web server (serves static files, proxies to FPM)
            containers.nextcloud-web = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Nextcloud nginx web server container";
                After = [
                  pods.nextcloud.ref
                  "nextcloud-app.service"
                ];
              };

              containerConfig = {
                image = "docker.io/nginxinc/nginx-unprivileged:alpine";
                pod = pods.nextcloud.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "nextcloud";
                  port = 8080;
                  subdomain = cfg.subdomain;
                  extraLabels = name: {
                    # CalDAV/CardDAV well-known URL redirects (required for mobile apps)
                    "traefik.http.middlewares.nextcloud-caldav.redirectregex.permanent" = "true";
                    "traefik.http.middlewares.nextcloud-caldav.redirectregex.regex" =
                      "^https://(.*)/.well-known/(card|cal)dav";
                    "traefik.http.middlewares.nextcloud-caldav.redirectregex.replacement" =
                      "https://$${1}/remote.php/dav/";

                    # WebFinger/NodeInfo well-known URL redirects (required for federation and social apps)
                    "traefik.http.middlewares.nextcloud-wellknown.redirectregex.permanent" = "true";
                    "traefik.http.middlewares.nextcloud-wellknown.redirectregex.regex" =
                      "^https://([^/]+)/.well-known/(webfinger|nodeinfo)(.*)";
                    "traefik.http.middlewares.nextcloud-wellknown.redirectregex.replacement" =
                      "https://$${1}/index.php/.well-known/$${2}$${3}";

                    # HSTS and security headers
                    "traefik.http.middlewares.nextcloud-headers.headers.stsSeconds" = "315360000";
                    "traefik.http.middlewares.nextcloud-headers.headers.stsIncludeSubdomains" = "true";

                    # Apply middlewares (NO authelia - Nextcloud has its own auth + OIDC)
                    "traefik.http.routers.${name}.middlewares" =
                      "nextcloud-caldav,nextcloud-wellknown,nextcloud-headers";
                  };
                };

                environments = {
                  TZ = "Europe/Amsterdam";
                };

                volumes = [
                  "${volumes.nextcloud_data.ref}:/var/www/html:ro"
                  "${nixosConfig.services.pods.nextcloud._nginxConfigFile}:/etc/nginx/nginx.conf:ro"
                ];
              };
            };

            # Container 5: Collabora Office (online document editing)
            containers.nextcloud-code = lib.mkIf cfg.collabora.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Collabora Office container";
                After = [ pods.nextcloud.ref ];
              };

              containerConfig = {
                image = "docker.io/collabora/code:latest";
                pod = pods.nextcloud.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "collabora";
                  port = 9980;
                  subdomain = cfg.collabora.subdomain;
                  extraLabels = name: {
                    # Forward HTTPS protocol header (SSL termination via Traefik)
                    "traefik.http.middlewares.collabora-headers.headers.customRequestHeaders.X-Forwarded-Proto" =
                      "https";
                    "traefik.http.routers.${name}.middlewares" = "collabora-headers";
                  };
                };

                environments = {
                  TZ = "Europe/Amsterdam";
                  # Nextcloud domain for WOPI integration
                  "aliasgroup1" = "https://${cfg.subdomain}.${domain}";
                  # Disable internal SSL (Traefik handles it)
                  # Disable mount namespaces for rootless Podman compatibility
                  "extra_params" = "--o:ssl.enable=false --o:ssl.termination=true --o:mount_namespaces=false";
                };

                environmentFiles = [ nixosConfig.sops.templates."nextcloud-collabora-secrets".path ];
              };
            };
            # Container 6: notify_push — Client Push server for desktop sync notifications
            containers.nextcloud-push = {
              autoStart = true;

              serviceConfig = {
                Restart = "on-failure";
                RestartSec = "10s";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Nextcloud notify_push client push server";
                After = [
                  pods.nextcloud.ref
                  "nextcloud-app.service"
                  "nextcloud-db.service"
                  "nextcloud-redis.service"
                ];
              };

              containerConfig = {
                image = "docker.io/library/nextcloud:33.0-fpm";
                pod = pods.nextcloud.ref;
                autoUpdate = "registry";
                user = "1001:998";
                exec = "/var/www/html/apps/notify_push/bin/x86_64/notify_push /var/www/html/config/config.php";

                volumes = [
                  "${volumes.nextcloud_data.ref}:/var/www/html:ro"
                ];

                environments = {
                  TZ = "Europe/Amsterdam";
                  PORT = "7867";
                  NEXTCLOUD_URL = "http://127.0.0.1:8080";
                };
              };
            };

            # Container 7: Nextcloud Whiteboard WebSocket server
            containers.nextcloud-whiteboard = lib.mkIf cfg.whiteboard.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Nextcloud Whiteboard real-time collaboration server";
                After = [ pods.nextcloud.ref ];
              };

              containerConfig = {
                image = "ghcr.io/nextcloud-releases/whiteboard:stable";
                pod = pods.nextcloud.ref;
                autoUpdate = "registry";

                environments = {
                  TZ = "Europe/Amsterdam";
                  MAX_UPLOAD_FILE_SIZE = "10";
                };

                environmentFiles = [ nixosConfig.sops.templates."nextcloud-whiteboard-secrets".path ];

                labels = mkTraefikLabels {
                  name = "nextcloud-whiteboard";
                  port = 3002;
                  subdomain = cfg.whiteboard.subdomain;
                  extraLabels = _: { };
                };
              };
            };
          };

        # Cron timer: run Nextcloud background jobs every 5 minutes
        systemd.user.timers.nextcloud-cron = {
          Unit.Description = "Run Nextcloud cron.php every 5 minutes";
          Timer = {
            OnBootSec = "5min";
            OnUnitActiveSec = "5min";
            Unit = "nextcloud-cron.service";
          };
          Install.WantedBy = [ "timers.target" ];
        };

        # User-space systemd services: cron + 4 AI workers
        # AI workers process tasks immediately rather than waiting for the 5-min cron cycle.
        # 4 parallel workers required by apps like context_chat.
        # -t 60: worker exits after 60 s so PHP/config changes are always picked up.
        # StartLimitInterval/Burst: allow rapid restarts without systemd giving up.
        systemd.user.services =
          let
            # Add app names here to have them installed and enabled on every boot.
            nextcloudApps = [
              "user_oidc"
              "notify_push"
              "previewgenerator"
              "calendar"
              "contacts"
              "deck"
              "tasks"
              "mail"
              "notes"
              "spreed"
              "richdocuments"
              "collectives"
              "whiteboard"
              "news"
              "forms"
              "tables"
              "cookbook"
              "assistant"
              "context_chat"
              "context_agent"
              "integration_openai"
              "music"
            ];

            aiWorkerScript = pkgs.writeShellScript "nextcloud-ai-worker" ''
              exec ${pkgs.podman}/bin/podman exec nextcloud-app \
                php occ background-job:worker -t 60 \
                'OC\TaskProcessing\SynchronousBackgroundJob'
            '';
            aiWorkerService = {
              Unit = {
                Description = "Nextcloud AI task processing worker";
                After = [ "nextcloud-app.service" ];
                StartLimitIntervalSec = 60;
                StartLimitBurst = 10;
              };
              Service = {
                ExecStart = "${aiWorkerScript}";
                Restart = "always";
              };
              Install.WantedBy = [ "default.target" ];
            };
          in
          {
            nextcloud-cron = {
              Unit = {
                Description = "Nextcloud background job (cron.php)";
                After = [ "nextcloud-app.service" ];
              };
              Service = {
                Type = "oneshot";
                ExecStart = "${pkgs.podman}/bin/podman exec nextcloud-app php -f /var/www/html/cron.php";
              };
            };

            # App setup: install+enable all apps, configure integrations.
            # Runs on every boot; all operations are idempotent.
            # app:install exits non-zero if already present (|| true absorbs it); app:enable is always safe.
            nextcloud-app-setup = {
              Unit = {
                Description = "Install, enable, and configure Nextcloud apps";
                After = [ "nextcloud-app.service" ];
              };
              Service = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${pkgs.writeShellScript "nextcloud-app-setup" ''
                  occ() { ${pkgs.podman}/bin/podman exec nextcloud-app php occ "$@"; }

                  for app in ${lib.concatStringsSep " " nextcloudApps}; do
                    occ app:install "$app" 2>/dev/null || true
                    occ app:enable "$app"
                  done

                  # Switch background jobs to OS cron
                  occ background:cron

                  # Collabora Office: set WOPI server URL and activate config
                  occ config:app:set richdocuments wopi_url --value "https://${cfg.collabora.subdomain}.${domain}"
                  occ richdocuments:activate-config

                  # notify_push: register the push endpoint in Nextcloud's DB
                  occ notify_push:setup "https://${cfg.subdomain}.${domain}/push"

                  ${lib.optionalString cfg.whiteboard.enable ''
                    # Whiteboard: set backend URL and JWT secret
                    occ app:enable whiteboard
                    occ config:app:set whiteboard collabBackendUrl --value "https://${cfg.whiteboard.subdomain}.${domain}"
                    occ config:app:set whiteboard jwt_secret_key --value "$(${pkgs.gnugrep}/bin/grep '^WHITEBOARD_JWT_SECRET=' ${nixosConfig.sops.templates."nextcloud-app-secrets".path} | ${pkgs.coreutils}/bin/cut -d= -f2- | ${pkgs.coreutils}/bin/tr -d '\n\r')"
                  ''}
                ''}";
              };
              Install.WantedBy = [ "default.target" ];
            };

            # Maintenance: update apps and repair DB. Runs after app-setup on every boot.
            # db:add-missing-indices runs first so repair benefits from proper indices.
            nextcloud-maintenance = {
              Unit = {
                Description = "Nextcloud app updates and database maintenance";
                After = [ "nextcloud-app-setup.service" ];
              };
              Service = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${pkgs.writeShellScript "nextcloud-maintenance" ''
                  occ() { ${pkgs.podman}/bin/podman exec nextcloud-app php occ "$@"; }

                  # Update all appstore-installed apps (not updated by image pulls)
                  occ app:update --all

                  # Add missing DB indices before repair for better query performance
                  occ db:add-missing-indices

                  # Full repair including expensive checks
                  occ maintenance:repair --include-expensive
                ''}";
              };
              Install.WantedBy = [ "default.target" ];
            };

            # Declarative user_oidc provider setup — idempotent, runs on every boot.
            # Configures the Authelia OIDC provider so all options live in Nix.
            # Runs after nextcloud-app-setup so user_oidc is installed first.
            nextcloud-oidc-setup = {
              Unit = {
                Description = "Configure user_oidc Authelia provider for Nextcloud";
                After = [ "nextcloud-app-setup.service" ];
              };
              Service = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${pkgs.writeShellScript "nextcloud-oidc-setup" ''
                  ${pkgs.podman}/bin/podman exec nextcloud-app php occ user_oidc:provider Authelia \
                    --clientid="nextcloud" \
                    --discoveryuri="https://${authCfg.authelia.subdomain}.${domain}/.well-known/openid-configuration" \
                    --endsessionendpointuri="https://${authCfg.authelia.subdomain}.${domain}/logout" \
                    --send-id-token-hint=1 \
                    --scope="openid profile email groups" \
                    --mapping-uid=preferred_username \
                    --mapping-display-name=name \
                    --mapping-email=email \
                    --mapping-avatar=picture \
                    --mapping-groups=nextcloud_groups \
                    --unique-uid=0 \
                    --group-provisioning=1
                  # Disable multiple user backends so user_oidc auto-redirects to Authelia
                  # (user_oidc reads this from its own app config as '0'/'1', not core)
                  ${pkgs.podman}/bin/podman exec nextcloud-app php occ config:app:set user_oidc allow_multiple_user_backends --value=0
                  # Re-grant admin role — lost after user_oidc takes over user management
                  ${pkgs.podman}/bin/podman exec nextcloud-app php occ group:adduser admin ${cfg.adminUser}
                ''}";
              };
              Install.WantedBy = [ "default.target" ];
            };

          }
          // lib.genAttrs
            (map (i: "nextcloud-ai-worker-${toString i}") (lib.range 1 4))
            (_: aiWorkerService);

      };

    # Secret management using sops-nix
    sops.secrets =
      lib.genAttrs
        [
          "nextcloud/admin_password"
          "nextcloud/mysql_root_password"
          "nextcloud/mysql_password"
          "nextcloud/redis_password"
          "nextcloud/collabora_password"
          "nextcloud/whiteboard_jwt_secret"
          "nextcloud/smtp_host"
          "nextcloud/smtp_port"
          "nextcloud/smtp_secure"
          "nextcloud/smtp_user"
          "nextcloud/smtp_password"
          "nextcloud/smtp_from_address"
        ]
        (_: {
          owner = "poddy";
          group = "poddy";
        });

    # MariaDB secrets (root and nextcloud user passwords)
    sops.templates."nextcloud-db-secrets" = {
      content = ''
        MYSQL_ROOT_PASSWORD=${config.sops.placeholder."nextcloud/mysql_root_password"}
        MYSQL_PASSWORD=${config.sops.placeholder."nextcloud/mysql_password"}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };

    # Redis config file (with password from sops)
    sops.templates."redis.conf" = {
      content = ''
        # Redis configuration for Nextcloud
        requirepass ${config.sops.placeholder."nextcloud/redis_password"}

        # Memory management
        maxmemory 512mb
        maxmemory-policy allkeys-lru

        # Persistence (AOF)
        appendonly yes
        appendfsync everysec

        # Network
        bind 127.0.0.1
        port 6379

        # Logging
        loglevel notice
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0444";
    };

    # Nextcloud app secrets (database, Redis, admin credentials, and SMTP)
    sops.templates."nextcloud-app-secrets" = {
      content = ''
        MYSQL_PASSWORD=${config.sops.placeholder."nextcloud/mysql_password"}
        REDIS_HOST_PASSWORD=${config.sops.placeholder."nextcloud/redis_password"}
        NEXTCLOUD_ADMIN_USER=${cfg.adminUser}
        NEXTCLOUD_ADMIN_PASSWORD=${config.sops.placeholder."nextcloud/admin_password"}
        SMTP_HOST=${config.sops.placeholder."nextcloud/smtp_host"}
        SMTP_PORT=${config.sops.placeholder."nextcloud/smtp_port"}
        SMTP_SECURE=${config.sops.placeholder."nextcloud/smtp_secure"}
        SMTP_USER=${config.sops.placeholder."nextcloud/smtp_user"}
        SMTP_PASSWORD=${config.sops.placeholder."nextcloud/smtp_password"}
        SMTP_FROM_ADDRESS=${config.sops.placeholder."nextcloud/smtp_from_address"}
        WHITEBOARD_JWT_SECRET=${config.sops.placeholder."nextcloud/whiteboard_jwt_secret"}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };

    # Whiteboard secrets (shared JWT secret between Nextcloud and whiteboard server)
    sops.templates."nextcloud-whiteboard-secrets" = lib.mkIf cfg.whiteboard.enable {
      content = ''
        JWT_SECRET_KEY=${config.sops.placeholder."nextcloud/whiteboard_jwt_secret"}
        NEXTCLOUD_URL=https://${cfg.subdomain}.${domain}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };

    # Collabora secrets (admin password)
    sops.templates."nextcloud-collabora-secrets" = lib.mkIf cfg.collabora.enable {
      content = ''
        username=admin
        password=${config.sops.placeholder."nextcloud/collabora_password"}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };
  };
}

# Post-deployment notes:
#
# Most setup is automated by systemd one-shot services that run on every boot:
#   nextcloud-app-setup   — installs/enables all apps, configures integrations
#   nextcloud-oidc-setup  — configures Authelia OIDC provider, re-grants admin role
#   nextcloud-maintenance — app:update --all, db:add-missing-indices, maintenance:repair
#   nextcloud-cron.timer  — runs cron.php every 5 minutes
#
# Check service status after first boot:
#   sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 systemctl --user status nextcloud-app-setup
#   sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 systemctl --user status nextcloud-oidc-setup
#   sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 systemctl --user status nextcloud-maintenance
#
# Manual steps still required:
#
# 1. Wait for database and Nextcloud initialization (before services can run):
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman logs nextcloud-db
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman logs nextcloud-app
#
# 2. Generate previews for existing files (only needed after bulk file migrations — not on fresh deploys):
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ preview:generate-all
#    (new files are handled automatically by the previewgenerator v5.12+ background job via cron.php)
#
# 3. Test OIDC login:
#    Visit https://cloud.nmsd.xyz and click "Login with Authelia"
#
# 4. Verify push server (self-test after containers are up):
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ notify_push:self-test

# ── Major version upgrade steps (e.g. 32 → 33) ──────────────────────────
#
# After changing the image tag and running nixos-rebuild switch:
#
# 1. Finalize the upgrade (if not auto-applied by entrypoint):
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ upgrade
#
# 2-5. Handled automatically by nextcloud-app-setup and nextcloud-maintenance on reboot.
#
# 6. Verify:
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ status
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ app:list
