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
                userns = "keep-id:uid=1001,gid=998";
              };
            };

            # Container 1: MariaDB 12.0 database
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
                image = "docker.io/library/mariadb:12.0";
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
                image = "docker.io/library/nextcloud:32-fpm";
                pod = pods.nextcloud.ref;
                autoUpdate = "registry";

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
                image = "docker.io/library/nginx:1.27-alpine";
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

                    # HSTS and security headers
                    "traefik.http.middlewares.nextcloud-headers.headers.stsSeconds" = "315360000";
                    "traefik.http.middlewares.nextcloud-headers.headers.stsIncludeSubdomains" = "true";

                    # Apply middlewares (NO authelia - Nextcloud has its own auth + OIDC)
                    "traefik.http.routers.${name}.middlewares" = "nextcloud-caldav,nextcloud-headers";
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

            # Container 5: Nextcloud cron job executor
            # Official recommendation: separate container for background jobs
            containers.nextcloud-cron = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Nextcloud cron job executor container";
                After = [
                  pods.nextcloud.ref
                  "nextcloud-web.service"
                ];
              };

              containerConfig = {
                image = "docker.io/library/nextcloud:32-fpm";
                pod = pods.nextcloud.ref;
                autoUpdate = "registry";

                # Override entrypoint to run cron daemon instead of FPM
                exec = "/cron.sh";

                environments = {
                  TZ = "Europe/Amsterdam";
                  MYSQL_HOST = "127.0.0.1";
                  MYSQL_DATABASE = "nextcloud";
                  MYSQL_USER = "nextcloud";
                };

                environmentFiles = [ nixosConfig.sops.templates."nextcloud-app-secrets".path ];

                volumes = [
                  "${volumes.nextcloud_data.ref}:/var/www/html:U"
                  "${nixosConfig.services.pods.nextcloud._configFile}:/var/www/html/config/zzz-nix-overrides.config.php:ro"
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

    # Collabora secrets (admin password)
    sops.templates."nextcloud-collabora-secrets" = lib.mkIf cfg.collabora.enable {
      content = ''
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
# 1. Wait for database and Nextcloud initialization:
#    podman logs nextcloud-db
#    podman logs nextcloud-app
#
# 2. Install OIDC Login app:
#    podman exec --user www-data nextcloud-app php occ app:install oidc_login
#    podman exec --user www-data nextcloud-app php occ app:enable oidc_login
#
# 3. Install Collabora integration (if enabled):
#    podman exec --user www-data nextcloud-app php occ app:install richdocuments
#    podman exec --user www-data nextcloud-app php occ app:enable richdocuments
#    podman exec --user www-data nextcloud-app php occ richdocuments:activate-config
#
# 4. Verify background jobs are using cron:
#    podman exec --user www-data nextcloud-app php occ background:cron
#
# 5. Run maintenance and repair:
#    podman exec --user www-data nextcloud-app php occ maintenance:repair --include-expensive
#
# 6. Check Nextcloud status:
#    podman exec --user www-data nextcloud-app php occ status
#
# 7. Test OIDC login:
#    Visit https://cloud.nmsd.xyz and click "Login with Authelia"
