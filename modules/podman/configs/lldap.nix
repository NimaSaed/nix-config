{ config, lib, pkgs, ... }:

let
  toml = pkgs.formats.toml { };
in
{
  options.services.pods.auth.lldap.configFile = lib.mkOption {
    type = lib.types.package;
    default = toml.generate "lldap_config.toml" {

      ## Technically, you don’t need this because it will be created
      ## automatically on startup. However, the seed will have the
      ## default value even though you set it in a variable, and
      ## there will be a warning in the logs, which drives me crazy.


      ## Database URL.
      ## This encodes the type of database (SQlite, MySQL, or PostgreSQL),
      ## the path, the user, password, and sometimes the mode (when relevant).
      ## Note: SQlite should come with "?mode=rwc" to create the DB if not present.
      ## Example URLs:
      ##   "postgres://postgres-user:password@postgres-server/my-database"
      ##   "mysql://mysql-user:password@mysql-server/my-database"
      ## Override with: LLDAP_DATABASE_URL
      database_url = "sqlite:///data/users.db?mode=rwc";

      ## Set to empty string to silence the warning when key_seed is
      ## provided via env var (otherwise lldap warns about ignoring key_file).
      key_file = "";

      # =====================================================================
      # All other lldap_config.toml options (override via LLDAP_* env vars):
      # =====================================================================
      #
      # verbose = false;
      #   Tune the logging to be more verbose.
      #   Override with: LLDAP_VERBOSE
      #
      # ldap_host = "0.0.0.0";
      #   Host address the LDAP server binds to.
      #   Use "::" for IPv6, "127.0.0.1" for localhost only.
      #   Override with: LLDAP_LDAP_HOST
      #
      # ldap_port = 3890;
      #   Port for the LDAP server.
      #   Override with: LLDAP_LDAP_PORT
      #
      # http_host = "0.0.0.0";
      #   Host address the HTTP server binds to.
      #   Override with: LLDAP_HTTP_HOST
      #
      # http_port = 17170;
      #   Port for the HTTP server (web UI and administration).
      #   Override with: LLDAP_HTTP_PORT
      #
      # http_url = "http://localhost";
      #   Public URL of the server, used for password reset links.
      #   Override with: LLDAP_HTTP_URL
      #
      # jwt_secret = "REPLACE_WITH_RANDOM";
      #   Random secret for JWT signature. Should be shared with apps
      #   consuming JWTs. Changing this invalidates all user sessions.
      #   Override with: LLDAP_JWT_SECRET or LLDAP_JWT_SECRET_FILE
      #
      # ldap_base_dn = "dc=example,dc=com";
      #   Base DN for LDAP. Usually your domain name, used as namespace
      #   for users. Currently set via LLDAP_LDAP_BASE_DN env var in auth.nix.
      #   Override with: LLDAP_LDAP_BASE_DN
      #
      # ldap_user_dn = "admin";
      #   Admin username. Creates LDAP user "cn=admin,ou=people,<base_dn>".
      #   Override with: LLDAP_LDAP_USER_DN
      #
      # ldap_user_email = "admin@example.com";
      #   Admin email. Only used when initially creating the admin user.
      #   Override with: LLDAP_LDAP_USER_EMAIL
      #
      # ldap_user_pass = "REPLACE_WITH_PASSWORD";
      #   Admin password (min 8 chars). Used for LDAP bind and web UI.
      #   Only used when initially creating the admin user.
      #   Override with: LLDAP_LDAP_USER_PASS or LLDAP_LDAP_USER_PASS_FILE
      #
      # force_ldap_user_pass_reset = false;
      #   Force reset admin password to ldap_user_pass value.
      #   Set to "always" to reset every time the server starts.
      #
      # key_file = "/data/private_key";
      #   Private key file for password storage. Not recommended, use key_seed.
      #   Randomly generated on first run if it doesn't exist.
      #   Override with: LLDAP_KEY_FILE
      #
      # key_seed = "RanD0m STR1ng";
      #   Seed to generate the server private key (min 12 chars recommended).
      #   Override with: LLDAP_KEY_SEED
      #
      # ignored_user_attributes = [ "sAMAccountName" ];
      #   Silence warnings for unknown user attributes requested by services.
      #
      # ignored_group_attributes = [ "mail" "userPrincipalName" ];
      #   Silence warnings for unknown group attributes requested by services.
      #
      # ---- SMTP Options [smtp_options] ----
      # Used for password reset emails.
      # Override with: LLDAP_SMTP_OPTIONS__<FIELD>
      #
      # smtp_options.enable_password_reset = true;
      # smtp_options.server = "smtp.gmail.com";
      # smtp_options.port = 587;
      # smtp_options.smtp_encryption = "TLS";  # "NONE", "TLS", or "STARTTLS"
      # smtp_options.user = "sender@gmail.com";
      # smtp_options.password = "password";
      # smtp_options.from = "LLDAP Admin <sender@gmail.com>";
      # smtp_options.reply_to = "Do not reply <noreply@localhost>";
      #
      # ---- LDAPS Options [ldaps_options] ----
      # Override with: LLDAP_LDAPS_OPTIONS__<FIELD>
      #
      # ldaps_options.enabled = true;
      # ldaps_options.port = 6360;
      # ldaps_options.cert_file = "/data/cert.pem";
      # ldaps_options.key_file = "/data/key.pem";
    };
    description = "Generated lldap_config.toml file";
  };
}
