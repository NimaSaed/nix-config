{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pods.nextcloud;
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

            # Container 3: Nextcloud 32 PHP-FPM backend
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
                image = "docker.io/library/nextcloud:32.0-fpm";
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
                  PHP_MEMORY_LIMIT = "512M";
                  PHP_UPLOAD_LIMIT = "10G";
                };

                environmentFiles = [ nixosConfig.sops.templates."nextcloud-app-secrets".path ];

                volumes = [
                  "${volumes.nextcloud_data.ref}:/var/www/html:U"
                  "${nixosConfig.services.pods.nextcloud._configFile}:/var/www/html/config/zzz-nix-overrides.config.php:ro"
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
                    "traefik.http.middlewares.nextcloud-caldav.redirectregex.regex" = "^https://(.*)/.well-known/(card|cal)dav";
                    "traefik.http.middlewares.nextcloud-caldav.redirectregex.replacement" = "https://$${1}/remote.php/dav/";

                    # WebFinger/NodeInfo well-known URL redirects (required for federation and social apps)
                    "traefik.http.middlewares.nextcloud-wellknown.redirectregex.permanent" = "true";
                    "traefik.http.middlewares.nextcloud-wellknown.redirectregex.regex" = "^https://([^/]+)/.well-known/(webfinger|nodeinfo)(.*)";
                    "traefik.http.middlewares.nextcloud-wellknown.redirectregex.replacement" = "https://$${1}/index.php/.well-known/$${2}$${3}";

                    # HSTS and security headers
                    "traefik.http.middlewares.nextcloud-headers.headers.stsSeconds" = "315360000";
                    "traefik.http.middlewares.nextcloud-headers.headers.stsIncludeSubdomains" = "true";

                    # Apply middlewares (NO authelia - Nextcloud has its own auth + OIDC)
                    "traefik.http.routers.${name}.middlewares" = "nextcloud-caldav,nextcloud-wellknown,nextcloud-headers";
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
                    "traefik.http.middlewares.collabora-headers.headers.customRequestHeaders.X-Forwarded-Proto" = "https";
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
            # Container 6: Nextcloud Whiteboard WebSocket server
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

        # Systemd timer to run Nextcloud background jobs every 5 minutes.
        # Executes cron.php inside the running nextcloud-app container, bypassing
        # the www-data UID mismatch in the official image's /cron.sh + busybox crond.
        systemd.user.services.nextcloud-cron = {
          Unit = {
            Description = "Nextcloud background job (cron.php)";
            After = [ "nextcloud-app.service" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${pkgs.podman}/bin/podman exec nextcloud-app php -f /var/www/html/cron.php";
          };
        };

        systemd.user.timers.nextcloud-cron = {
          description = "Run Nextcloud cron.php every 5 minutes";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "5min";
            OnUnitActiveSec = "5min";
            Unit = "nextcloud-cron.service";
          };
        };
      };

    # Secret management using sops-nix
    sops.secrets = lib.genAttrs [
      "nextcloud/admin_password"
      "nextcloud/mysql_root_password"
      "nextcloud/mysql_password"
      "nextcloud/redis_password"
      "nextcloud/oidc_client_secret"
      "nextcloud/collabora_password"
      "nextcloud/whiteboard_jwt_secret"
    ] (_: {
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

    # Nextcloud app secrets (database, Redis, admin credentials, and OIDC)
    # CRITICAL: oidc_client_secret must be PLAINTEXT (not the PBKDF2 hash stored in authelia/)
    sops.templates."nextcloud-app-secrets" = {
      content = ''
        MYSQL_PASSWORD=${config.sops.placeholder."nextcloud/mysql_password"}
        REDIS_HOST_PASSWORD=${config.sops.placeholder."nextcloud/redis_password"}
        NEXTCLOUD_ADMIN_USER=${cfg.adminUser}
        NEXTCLOUD_ADMIN_PASSWORD=${config.sops.placeholder."nextcloud/admin_password"}
        OIDC_CLIENT_SECRET=${config.sops.placeholder."nextcloud/oidc_client_secret"}
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

# Post-deployment manual steps (run AFTER first boot):
#
# NOTE: Container runs as UID 1001:998 (poddy), so occ commands run without --user flag
#
# 1. Wait for database and Nextcloud initialization:
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman logs nextcloud-db
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman logs nextcloud-app
#
# 2. Install OIDC Login app:
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ app:install oidc_login
#
# 3. Install Collabora integration (if enabled):
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ app:install richdocuments
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ config:app:set richdocuments wopi_url --value="https://office.nmsd.xyz"
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ richdocuments:activate-config
#
# 4. Switch background jobs to cron mode and trigger an immediate run:
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ background:cron
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-cron php -f /var/www/html/cron.php
#
# 5. Run maintenance, repair, and add missing DB indices:
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ maintenance:repair --include-expensive
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ db:add-missing-indices
#
# 6. Check code integrity and Nextcloud status:
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ integrity:check-core
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ status
#
# 7. Configure Whiteboard real-time collaboration (if enabled):
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ config:app:set whiteboard collabBackendUrl --value="https://whiteboard.nmsd.xyz"
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ config:app:set whiteboard jwt_secret_key --value="$(sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 grep JWT_SECRET_KEY /run/secrets/rendered/nextcloud-whiteboard-secrets | cut -d= -f2)"
#
# 8. Test OIDC login:
#    Visit https://cloud.nmsd.xyz and click "Login with Authelia"
#
# 9. Generate previews for existing files (required for Photos app):
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ app:install previewgenerator
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ preview:generate-all
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman exec nextcloud-app php occ preview:pre-generate
