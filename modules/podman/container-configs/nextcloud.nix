{ config, lib, pkgs, ... }:

let
  inherit (config.services.pods) domain;
  cfg = config.services.pods.nextcloud;
  authCfg = config.services.pods.auth;
in
{
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

        // Phone number validation region
        'default_phone_region' => '${cfg.phoneRegion}',

        // Locale must be region-specific (not bare 'en') to avoid Photos app crash
        // See: https://help.nextcloud.com/t/photos-page-blank-when-using-en-locale/240664
        'default_language' => 'en',
        'default_locale' => 'en_US',

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

        // OIDC Login (Authelia integration)
        // Requires: php occ app:install oidc_login
        'oidc_login_provider_url' => 'https://${authCfg.authelia.subdomain}.${domain}',
        'oidc_login_client_id' => 'nextcloud',
        'oidc_login_client_secret' => getenv('OIDC_CLIENT_SECRET'),  // From environmentFiles
        'oidc_login_auto_redirect' => true,
        'oidc_login_logout_url' => 'https://${authCfg.authelia.subdomain}.${domain}/logout',
        'oidc_login_button_text' => 'Login with Authelia',
        'lost_password_link' => 'disabled',
        'hide_login_form' => true,
        'oidc_login_use_id_token' => false,
        'oidc_login_attributes' => array (
          'id' => 'preferred_username',
          'name' => 'name',
          'mail' => 'email',
          'groups' => 'groups',
          'is_admin' => 'is_nextcloud_admin',
        ),
        'oidc_login_default_group' => 'oidc',
        'oidc_login_scope' => 'openid profile email groups nextcloud_userinfo',
        'oidc_login_disable_registration' => false,
        'oidc_login_remap_users' => true,
        'oidc_login_tls_verify' => true,

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

        // Performance and logging
        'loglevel' => 2,  // Warnings and above
        'log_type' => 'file',
        'maintenance_window_start' => 1,  // 1 AM UTC for background maintenance
      );
    '';
    description = "Generated Nextcloud configuration file with OIDC, Redis, and Collabora settings";
  };
}
