{ config, lib, pkgs, ... }:

let
  domain = config.services.pods.domain;
  authCfg = config.services.pods.auth;
  toolsCfg = config.services.pods.tools;
  mediaCfg = config.services.pods.media;
  rpCfg = config.services.pods.reverse-proxy;

  # Convert "example.com" to "dc=example,dc=com" for LDAP Base DN
  domainToBaseDN =
    d: lib.concatStringsSep "," (map (part: "dc=${part}") (lib.splitString "." d));
  baseDN = domainToBaseDN domain;
in
{
  options.services.pods.auth.authelia.configFile = lib.mkOption {
    type = lib.types.package;
    # Uses pkgs.writeText (not pkgs.formats.yaml) because JWKS and client_secret
    # live inside YAML arrays, and Authelia doesn't support env var overrides for
    # array-indexed paths. Instead, we embed Authelia template expressions ({{ }})
    # that read secrets from mounted files at container startup.
    # Enable with: X_AUTHELIA_CONFIG_FILTERS=template
    default = pkgs.writeText "configuration.yml" ''
      theme: auto

      server:
        address: "tcp://:9091"

      log:
        level: debug

      totp:
        issuer: "${authCfg.authelia.subdomain}.${domain}"

      access_control:
        default_policy: deny
        rules:
          - domain:
              - "${toolsCfg.itTools.subdomain}.${domain}"
              - "${mediaCfg.jellyfin.subdomain}.${domain}"
            policy: bypass
          - domain:
              - "${toolsCfg.homepage.subdomain}.${domain}"
              - "changedetection.${domain}"
            policy: one_factor
          - domain:
              - "${rpCfg.subdomain}.${domain}"
              - "${authCfg.lldap.subdomain}.${domain}"
              - "scrypted.${domain}"
            policy: two_factor

      session:
        cookies:
          - name: authelia_session
            domain: "${domain}"
            authelia_url: "https://${authCfg.authelia.subdomain}.${domain}"
            expiration: "24 hour"
            inactivity: "24 hour"
            default_redirection_url: "https://${toolsCfg.homepage.subdomain}.${domain}"

      regulation:
        max_retries: 3
        find_time: "2 minutes"
        ban_time: "5 minutes"

      storage:
        local:
          path: "/config/db.sqlite3"

      notifier:
        disable_startup_check: false
        smtp:
          # address and username provided via env vars from sops template
          sender: "Authelia <info@${domain}>"
          disable_require_tls: false

      # Using LLDAP for authentication (not local file/SQLite user DB).
      # To switch to local file auth in the future, replace with:
      #   authentication_backend:
      #     file:
      #       path: "/config/users.yml"
      authentication_backend:
        ldap:
          implementation: lldap
          address: "ldaps://${authCfg.lldap.subdomain}.${domain}:636"
          tls:
            skip_verify: true
          base_dn: "${baseDN}"
          user: "uid=admin,ou=people,${baseDN}"

      definitions:
        user_attributes:
          is_nextcloud_admin:
            expression: '"nextcloud-admins" in groups'

      identity_providers:
        oidc:
          claims_policies:
            nextcloud_userinfo:
              custom_claims:
                is_nextcloud_admin: {}
          scopes:
            nextcloud_userinfo:
              claims:
                - is_nextcloud_admin

          jwks:
            - key_id: 'authelia_key'
              key: {{ secret "/secrets/oidc_jwks_key" | mindent 10 "|" | msquote }}
              certificate_chain: {{ secret "/secrets/oidc_jwks_cert" | mindent 10 "|" | msquote }}

          clients:
            - client_id: nextcloud
              client_name: NextCloud
              client_secret: '{{ secret "/secrets/nextcloud_client_secret" }}'
              public: false
              authorization_policy: two_factor
              require_pkce: true
              pkce_challenge_method: S256
              claims_policy: nextcloud_userinfo
              redirect_uris:
                - "https://cloud.${domain}/apps/oidc_login/oidc"
              scopes:
                - openid
                - profile
                - email
                - groups
                - nextcloud_userinfo
              response_types:
                - code
              grant_types:
                - authorization_code
              consent_mode: implicit
              access_token_signed_response_alg: none
              userinfo_signed_response_alg: none
              token_endpoint_auth_method: client_secret_basic
            - client_id: jellyfin
              client_name: Jellyfin
              client_secret: '{{ secret "/secrets/jellyfin_client_secret" }}'
              public: false
              authorization_policy: one_factor
              require_pkce: true
              pkce_challenge_method: S256
              redirect_uris:
                - "https://${mediaCfg.jellyfin.subdomain}.${domain}/sso/OID/redirect/authelia"
              scopes:
                - openid
                - profile
                - groups
              response_types:
                - code
              grant_types:
                - authorization_code
              consent_mode: implicit
              access_token_signed_response_alg: none
              userinfo_signed_response_alg: none
              token_endpoint_auth_method: client_secret_post
    '';
    description = "Generated Authelia configuration.yml";
  };
}
