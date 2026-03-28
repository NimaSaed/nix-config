{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (config.services.pods) domain;
  cfg = config.services.pods.nextcloud;
in
{
  options.services.pods.nextcloud._fpmPoolFile = lib.mkOption {
    type = lib.types.package;
    internal = true;
    default = pkgs.writeText "zzz-nix-fpm-pool.conf" ''
      [www]
      pm = dynamic
      pm.max_children = 30
      pm.start_servers = 8
      pm.min_spare_servers = 4
      pm.max_spare_servers = 16
      pm.max_requests = 500
    '';
    description = "Custom PHP-FPM pool overrides for performance tuning";
  };

  options.services.pods.nextcloud._configFile = lib.mkOption {
    type = lib.types.package;
    internal = true;
    default = pkgs.writeText "zzz-nix-overrides.config.php" ''
      <?php
      // Nextcloud declarative configuration overrides
      // This file is loaded AFTER the auto-generated config.php due to the zzz- prefix
      $CONFIG = array (
        // Trusted domains and proxies
        'trusted_domains' => array (
          0 => '${cfg.subdomain}.${domain}',
        ),
        'trusted_proxies' => array (
          0 => '10.88.0.0/16',  // Podman default subnet (Traefik pod)
          1 => '127.0.0.1',     // notify_push (same pod, connects directly to nginx)
        ),

        // Protocol and host overrides (behind HTTPS reverse proxy)
        'overwrite.cli.url' => 'https://${cfg.subdomain}.${domain}',
        'overwriteprotocol' => 'https',
        'overwritehost'     => '${cfg.subdomain}.${domain}',

        // Phone number validation region
        'default_phone_region' => '${cfg.phoneRegion}',

        // Locale must be region-specific (not bare 'en') to avoid Photos app crash
        // See: https://help.nextcloud.com/t/photos-page-blank-when-using-en-locale/240664
        'default_language' => 'en_GB',
        'default_locale' => 'en_GB',

        // Redis configuration for caching and file locking
        'memcache.local' => '\\OC\\Memcache\\APCu',
        'memcache.distributed' => '\\OC\\Memcache\\Redis',
        'memcache.locking' => '\\OC\\Memcache\\Redis',
        'redis' => array (
          'host' => '127.0.0.1',
          'port' => 6379,
          'password' => getenv('REDIS_HOST_PASSWORD'),  // From environmentFiles
        ),

        // Database configuration
        'mysql.utf8mb4' => true,

        // Allow Nextcloud's HTTP client to reach internal services (e.g. Authelia on 10.10.10.x).
        // user_oidc uses Nextcloud's GuzzleHttp client which enforces SSRF protection by default.
        // No per-IP whitelist exists in Nextcloud — this is the documented approach for internal OIDC.
        'allow_local_remote_servers' => true,

        // user_oidc (official Nextcloud OIDC backend)
        // Provider is configured declaratively via nextcloud-oidc-setup.service
        // Requires: php occ app:install user_oidc
        // user_oidc auto-enables PKCE when the discovery doc advertises code_challenge_methods_supported.
        // Authelia is configured as a public client (require_pkce=true, no secret) to match this behavior.
        'user_oidc' => array (
          'single_logout'                        => true,
          'auto_provision'                       => true,
          'soft_auto_provision'                  => true,  // links OIDC login to existing accounts on migration
          'hide_login_form'                      => true,  // hides local login form; admin bypass: /login?direct=1
        ),
        'lost_password_link' => 'disabled',
        'hide_login_form' => true,

        // SMTP mail configuration (all values injected via sops environmentFiles)
        'mail_smtpmode' => 'smtp',
        'mail_smtphost' => getenv('SMTP_HOST'),
        'mail_smtpport' => (int)getenv('SMTP_PORT'),
        'mail_smtpauth' => true,
        'mail_smtpauthtype' => 'LOGIN',
        'mail_smtpsecure' => getenv('SMTP_SECURE'),  // 'ssl' = implicit TLS (port 465)
        'mail_smtpname' => getenv('SMTP_USER'),
        'mail_smtppassword' => getenv('SMTP_PASSWORD'),
        'mail_from_address' => getenv('SMTP_FROM_ADDRESS'),
        'mail_domain' => '${domain}',

        ${lib.optionalString cfg.collabora.enable ''
          // Collabora Online integration
          // Requires: php occ app:install richdocuments
        ''}

        // Preview generation (required for Photos app)
        'enable_previews' => true,
        'enabledPreviewProviders' => array (
          'OC\Preview\PNG',
          'OC\Preview\JPEG',
          'OC\Preview\GIF',
          'OC\Preview\BMP',
          'OC\Preview\HEIC',
          'OC\Preview\TIFF',
          'OC\Preview\SVG',
          'OC\Preview\Movie',  // Covers all video formats (MP4, MKV, AVI, MOV, etc.)
        ),
        'preview_max_x' => 2048,
        'preview_max_y' => 2048,
        'jpeg_quality' => 60,

        // Server identifier (recommended for multi-PHP-server setups)
        'server_id' => 'nextcloud-app',

        // Performance and logging
        'loglevel' => 2,  // Warnings and above
        'log_type' => 'file',
        'maintenance_window_start' => 1,  // 1 AM UTC for background maintenance
      );
    '';
    description = "Generated Nextcloud configuration file with OIDC, Redis, and Collabora settings";
  };
}
