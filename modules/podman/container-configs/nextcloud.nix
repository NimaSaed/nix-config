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
        ),

        // Protocol and host overrides (behind HTTPS reverse proxy)
        'overwrite.cli.url' => 'https://${cfg.subdomain}.${domain}',
        'overwriteprotocol' => 'https',

        // Phone number validation region
        'default_phone_region' => '${cfg.phoneRegion}',

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
        'oidc_login_auto_redirect' => false,
        'oidc_login_end_session_redirect' => true,
        'oidc_login_button_text' => 'Login with Authelia',
        'oidc_login_hide_password_form' => false,
        'oidc_login_use_id_token' => false,
        'oidc_login_attributes' => array (
          'id' => 'preferred_username',
          'name' => 'name',
          'mail' => 'email',
          'groups' => 'groups',
        ),
        'oidc_login_default_group' => 'oidc',
        'oidc_login_scope' => 'openid profile email groups nextcloud_userinfo',
        'oidc_login_disable_registration' => true,
        'oidc_login_remap_users' => true,
        'oidc_login_tls_verify' => true,

        ${lib.optionalString cfg.collabora.enable ''
        // Collabora Online integration
        // Requires: php occ app:install richdocuments
        'richdocuments_wopi_url' => 'https://${cfg.collabora.subdomain}.${domain}',
        ''}

        // Performance and logging
        'loglevel' => 2,  // Warnings and above
        'log_type' => 'file',
        'maintenance_window_start' => 1,  // 1 AM UTC for background maintenance
      );
    '';
    description = "Generated Nextcloud configuration file with OIDC, Redis, and Collabora settings";
  };
}
