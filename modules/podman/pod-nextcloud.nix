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
    ./container-configs/davmail.nix
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

    talk = {
      hpb = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Talk High-performance Backend (NATS + signaling on chestnut; coturn on walnut)";
        };
        subdomain = lib.mkOption {
          type = lib.types.str;
          default = "talk";
          description = "Subdomain for the HPB signaling WebSocket server";
        };
        turnSubdomain = lib.mkOption {
          type = lib.types.str;
          default = "turn";
          description = "Subdomain for the coturn TURN server. DNS must point to walnut's public IP.";
        };
        turnPort = lib.mkOption {
          type = lib.types.port;
          default = 3478;
          description = "Port of the coturn TURN server";
        };
      };
    };

    davmail = {
      enable = lib.mkEnableOption "DavMail Exchange/O365 gateway (IMAP, SMTP, CalDAV, LDAP)";

      accounts = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              tenantId = lib.mkOption {
                type = lib.types.str;
                description = ''
                  Azure AD tenant ID (GUID from Azure portal → Microsoft Entra ID → Overview).
                  Restricts OAuth2 authentication to this specific O365 tenant.
                  Ports are auto-assigned by account order (alphabetical key sort):
                    account 0: IMAP 1143, SMTP 1025, CalDAV 1080, LDAP 1389
                    account 1: IMAP 1243, SMTP 1125, CalDAV 1180, LDAP 1489
                '';
              };
            };
          }
        );
        default = { };
        description = "DavMail account configurations. One entry per O365 tenant.";
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
          lib.recursiveUpdate
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
                  "${nixosConfig.services.pods.nextcloud._phpIniFile}:/usr/local/etc/php/conf.d/zzz-nix-opcache.ini:ro"
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

            # Container 8: NATS message broker for Talk HPB
            containers.nextcloud-talk-nats = lib.mkIf cfg.talk.hpb.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "NATS message broker for Nextcloud Talk HPB";
                After = [ pods.nextcloud.ref ];
              };

              containerConfig = {
                image = "docker.io/library/nats:2-alpine";
                pod = pods.nextcloud.ref;
                autoUpdate = "registry";
                exec = "-js"; # enable JetStream
                environments.TZ = "Europe/Amsterdam";
              };
            };

            # Container 9: nextcloud-spreed-signaling HPB server
            containers.nextcloud-talk = lib.mkIf cfg.talk.hpb.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Nextcloud Talk HPB signaling server";
                After = [
                  pods.nextcloud.ref
                  "nextcloud-talk-nats.service"
                ];
              };

              containerConfig = {
                image = "ghcr.io/strukturag/nextcloud-spreed-signaling:latest";
                pod = pods.nextcloud.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "talk";
                  port = 8088;
                  subdomain = cfg.talk.hpb.subdomain;
                };

                environments.TZ = "Europe/Amsterdam";

                volumes = [
                  "${nixosConfig.sops.templates."nextcloud-talk-signaling.conf".path}:/config/server.conf:ro"
                ];
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
          }
          # DavMail: one container + one token-cache volume per O365 account
          (lib.optionalAttrs cfg.davmail.enable (
            {
              volumes = lib.mapAttrs' (name: _:
                lib.nameValuePair "nextcloud_davmail_${name}" { volumeConfig = { }; }
              ) cfg.davmail.accounts;
            }
            //
            {
              containers = builtins.listToAttrs (
                map (acct: {
                  name = "nextcloud-davmail-${acct.name}";
                  value = {
                    autoStart = true;

                    serviceConfig = {
                      Restart = "always";
                      TimeoutStopSec = 70;
                    };

                    unitConfig = {
                      Description = "DavMail O365 gateway for account: ${acct.name}";
                      After = [ pods.nextcloud.ref ];
                    };

                    containerConfig = {
                      image = "docker.io/kran0/davmail-docker:latest";
                      pod = pods.nextcloud.ref;
                      autoUpdate = "registry";

                      volumes = [
                        "${nixosConfig.services.pods.nextcloud.davmail._configFiles.${acct.name}}:/etc/davmail/davmail.properties:ro"
                        "${volumes."nextcloud_davmail_${acct.name}".ref}:/data:U"
                      ];

                      environments = {
                        TZ = "Europe/Amsterdam";
                      };
                    };
                  };
                }) nixosConfig.services.pods.nextcloud.davmail._indexedAccounts
              );
            }
          ));

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

                  # Set server identifier (silences admin panel warning)
                  occ config:system:set server_id --value "nextcloud-app"

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
            (_: aiWorkerService)
          // lib.optionalAttrs cfg.talk.hpb.enable {
            nextcloud-talk-setup = {
              Unit = {
                Description = "Configure Nextcloud Talk HPB (TURN + signaling)";
                After = [ "nextcloud-app-setup.service" ];
              };
              Service = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${pkgs.writeShellScript "nextcloud-talk-setup" ''
                  occ() { ${pkgs.podman}/bin/podman exec nextcloud-app php occ "$@"; }

                  TURN_SECRET=$(${pkgs.gnugrep}/bin/grep '^TURN_SECRET=' \
                    ${nixosConfig.sops.templates."nextcloud-talk-secrets".path} | \
                    ${pkgs.coreutils}/bin/cut -d= -f2- | ${pkgs.coreutils}/bin/tr -d '\n\r')

                  SIGNALING_SECRET=$(${pkgs.gnugrep}/bin/grep '^SIGNALING_SECRET=' \
                    ${nixosConfig.sops.templates."nextcloud-talk-secrets".path} | \
                    ${pkgs.coreutils}/bin/cut -d= -f2- | ${pkgs.coreutils}/bin/tr -d '\n\r')

                  occ config:app:set spreed turn_servers \
                    --value="[{\"server\":\"${cfg.talk.hpb.turnSubdomain}.${domain}:${toString cfg.talk.hpb.turnPort}\",\"secret\":\"$TURN_SECRET\",\"protocols\":\"udp,tcp\"}]"

                  occ config:app:set spreed signaling_servers \
                    --value="{\"servers\":[{\"server\":\"https://${cfg.talk.hpb.subdomain}.${domain}\",\"verify\":true}],\"secret\":\"$SIGNALING_SECRET\"}"
                ''}";
              };
              Install.WantedBy = [ "default.target" ];
            };
          };

      };

    # Secret management using sops-nix
    sops.secrets =
      lib.genAttrs
        (
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
          ++ lib.optionals cfg.talk.hpb.enable [
            "nextcloud/turn_secret"
            "nextcloud/signaling_secret"
            "nextcloud/signaling_hashkey"
            "nextcloud/signaling_blockkey"
          ]
        )
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

    # Talk HPB: env file read by nextcloud-talk-setup service
    sops.templates."nextcloud-talk-secrets" = lib.mkIf cfg.talk.hpb.enable {
      content = ''
        TURN_SECRET=${config.sops.placeholder."nextcloud/turn_secret"}
        SIGNALING_SECRET=${config.sops.placeholder."nextcloud/signaling_secret"}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };

    # Talk HPB: signaling server TOML config, mounted read-only into the container
    # mode 0444: container process runs as non-root UID, needs world-readable (same as redis.conf)
    sops.templates."nextcloud-talk-signaling.conf" = lib.mkIf cfg.talk.hpb.enable {
      content = ''
        [http]
        listen = 0.0.0.0:8088

        [app]
        debug = true

        [sessions]
        hashkey = ${config.sops.placeholder."nextcloud/signaling_hashkey"}
        blockkey = ${config.sops.placeholder."nextcloud/signaling_blockkey"}

        [clients]
        internalsecret = ${config.sops.placeholder."nextcloud/signaling_secret"}

        [backend]
        backends = nextcloud
        allowall = false
        timeout = 10
        connectionsperhost = 8

        [nextcloud]
        urls = https://${cfg.subdomain}.${domain}
        secret = ${config.sops.placeholder."nextcloud/signaling_secret"}

        [nats]
        url = nats://127.0.0.1:4222

        [turn]
        apikey = turn
        secret = ${config.sops.placeholder."nextcloud/turn_secret"}
        servers = turn:${cfg.talk.hpb.turnSubdomain}.${domain}:${toString cfg.talk.hpb.turnPort}?transport=udp,turn:${cfg.talk.hpb.turnSubdomain}.${domain}:${toString cfg.talk.hpb.turnPort}?transport=tcp
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0444";
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
# 1. Generate previews for existing files (only needed after bulk file migrations — not on fresh deploys):
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ preview:generate-all
