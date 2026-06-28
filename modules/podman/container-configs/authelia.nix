{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (config.services.pods) domain;
  authCfg = config.services.pods.auth;
  vaultwardenCfg = config.services.pods.vaultwarden;
  toolsCfg = config.services.pods.tools;
  mediaCfg = config.services.pods.media;
  rpCfg = config.services.pods.reverse-proxy;
  nextcloudCfg = config.services.pods.nextcloud;
  shCfg = config.services.pods.smart-home;
  immichCfg = config.services.pods.immich;
  aiCfg = config.services.pods.ai;
  paperlessCfg = config.services.pods.paperless;
  baseDN = authCfg._baseDN;

  # Emit an OIDC client only when its backing service is enabled, so a host that
  # runs Authelia without a given pod (or without the haos module) still evaluates.
  mkOidcClient =
    enabled: body:
    lib.optionalString enabled (
      "\n"
      + lib.concatMapStringsSep "\n" (line: if line == "" then "" else "      " + line) (
        lib.splitString "\n" (lib.removeSuffix "\n" body)
      )
    );

  oidcClients =
    (mkOidcClient nextcloudCfg.enable ''
      - client_id: nextcloud
        client_name: NextCloud
        # Public client: user_oidc auto-enables PKCE when the discovery doc advertises
        # code_challenge_methods_supported. PKCE S256 replaces the client secret as
        # proof of identity — token_endpoint_auth_method=none with PKCE is secure.
        public: true
        authorization_policy: nextcloud_access
        claims_policy: nextcloud_userinfo
        require_pkce: true
        pkce_challenge_method: S256
        redirect_uris:
          - "https://${nextcloudCfg.subdomain}.${domain}/apps/user_oidc/code"
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
    '')
    + (mkOidcClient mediaCfg.jellyfin.enable ''
      - client_id: jellyfin
        client_name: Jellyfin
        client_secret: '{{ secret "/secrets/jellyfin_client_secret" }}'
        public: false
        authorization_policy: jellyfin_access
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
    '')
    + (mkOidcClient aiCfg.litellm.enable ''
      - client_id: litellm
        client_name: LiteLLM
        client_secret: '{{ secret "/secrets/litellm_client_secret" }}'
        public: false
        authorization_policy: litellm_access
        claims_policy: litellm_policy
        require_pkce: true
        pkce_challenge_method: S256
        redirect_uris:
          - "https://${aiCfg.litellm.subdomain}.${domain}/sso/callback"
        scopes:
          - openid
          - profile
          - email
          - litellm_scope
        response_types:
          - code
        grant_types:
          - authorization_code
        consent_mode: implicit
        access_token_signed_response_alg: none
        userinfo_signed_response_alg: none
        token_endpoint_auth_method: client_secret_basic
    '')
    + (mkOidcClient immichCfg.enable ''
      - client_id: immich
        client_name: Immich
        client_secret: '{{ secret "/secrets/immich_client_secret" }}'
        public: false
        authorization_policy: immich_access
        claims_policy: immich_policy
        redirect_uris:
          - "https://${immichCfg.subdomain}.${domain}/auth/login"
          - "https://${immichCfg.subdomain}.${domain}/user-settings"
          - "app.immich:///oauth-callback"
        scopes:
          - openid
          - profile
          - email
          - immich_scope
        response_types:
          - code
        grant_types:
          - authorization_code
        consent_mode: implicit
        access_token_signed_response_alg: none
        userinfo_signed_response_alg: none
        token_endpoint_auth_method: client_secret_post
    '')
    + (mkOidcClient vaultwardenCfg.enable ''
      - client_id: vaultwarden
        client_name: Vaultwarden
        client_secret: '{{ secret "/secrets/vaultwarden_client_secret" }}'
        public: false
        authorization_policy: vaultwarden_access
        require_pkce: true
        pkce_challenge_method: S256
        redirect_uris:
          - "https://${vaultwardenCfg.subdomain}.${domain}/identity/connect/oidc-signin"
        scopes:
          - openid
          - profile
          - email
        response_types:
          - code
        grant_types:
          - authorization_code
        consent_mode: implicit
        access_token_signed_response_alg: none
        userinfo_signed_response_alg: none
        token_endpoint_auth_method: client_secret_basic
    '')
    + (mkOidcClient aiCfg.openwebui.enable ''
      - client_id: openwebui
        client_name: Open WebUI
        client_secret: '{{ secret "/secrets/openwebui_client_secret" }}'
        public: false
        authorization_policy: openwebui_access
        require_pkce: true
        pkce_challenge_method: S256
        redirect_uris:
          - "https://${aiCfg.openwebui.subdomain}.${domain}/oauth/oidc/callback"
        scopes:
          - openid
          - profile
          - email
          - groups
        response_types:
          - code
        grant_types:
          - authorization_code
        consent_mode: implicit
        access_token_signed_response_alg: none
        userinfo_signed_response_alg: none
        token_endpoint_auth_method: client_secret_basic
    '')
    + (mkOidcClient (config.services.haos.enable or false) ''
      - client_id: home-assistant
        client_name: Home Assistant
        client_secret: '{{ secret "/secrets/homeassistant_client_secret" }}'
        public: false
        authorization_policy: homeassistant_access
        require_pkce: true
        pkce_challenge_method: S256
        redirect_uris:
          - "https://${config.services.haos.subdomain}.${domain}/auth/oidc/callback"
        scopes:
          - openid
          - profile
          - groups
        response_types:
          - code
        grant_types:
          - authorization_code
        consent_mode: implicit
        token_endpoint_auth_method: client_secret_post
    '')
    + (mkOidcClient paperlessCfg.enable ''
      - client_id: paperless
        client_name: Paperless-ngx
        client_secret: '{{ secret "/secrets/paperless_client_secret" }}'
        public: false
        authorization_policy: paperless_access
        require_pkce: true
        pkce_challenge_method: S256
        redirect_uris:
          - "https://${paperlessCfg.subdomain}.${domain}/accounts/oidc/authelia/login/callback/"
        scopes:
          - openid
          - profile
          - email
          - groups
        response_types:
          - code
        grant_types:
          - authorization_code
        consent_mode: implicit
        token_endpoint_auth_method: client_secret_basic
    '');
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
        buffers:
          read: 8192
          write: 8192
        timeouts:
          read: '30s'
          write: '30s'
          idle: '120s'

      log:
        level: info

      totp:
        issuer: "${authCfg.authelia.subdomain}.${domain}"

      access_control:
        default_policy: deny
        rules:
          - domain:
              - "${toolsCfg.itTools.subdomain}.${domain}"
            policy: bypass
          - domain:
              - "${toolsCfg.homepage.subdomain}.${domain}"
            policy: one_factor
            subject:
              - 'group:homepage-users'
          - domain:
              - "${mediaCfg.sonarr.subdomain}.${domain}"
              - "${mediaCfg.radarr.subdomain}.${domain}"
              - "${mediaCfg.nzbget.subdomain}.${domain}"
              - "${mediaCfg.seerr.subdomain}.${domain}"
            policy: one_factor
            subject:
              - 'group:media-admins'
          - domain:
              - "${rpCfg.subdomain}.${domain}"
              - "${toolsCfg.dozzle.subdomain}.${domain}"
            policy: two_factor
            subject:
              - 'group:admins'
          - domain:
              - "${authCfg.lldap.subdomain}.${domain}"
            policy: two_factor
            subject:
              - 'group:lldap_admin'
          - domain:
              - "${shCfg.scrypted.subdomain}.${domain}"
            policy: two_factor
            subject:
              - 'group:scrypted-users'
          - domain:
              - "${toolsCfg.changedetection.subdomain}.${domain}"
            policy: two_factor
            subject:
              - 'group:changedetection-users'
          - domain:
              - "${paperlessCfg.ai.subdomain}.${domain}"
              - "${paperlessCfg.gpt.subdomain}.${domain}"
            policy: two_factor
            subject:
              - 'group:admins'

      session:
        cookies:
          - name: authelia_session
            domain: "${domain}"
            authelia_url: "https://${authCfg.authelia.subdomain}.${domain}"
            expiration: "24 hour"
            inactivity: "24 hour"
            default_redirection_url: "https://${toolsCfg.homepage.subdomain}.${domain}"
        redis:
          host: '127.0.0.1'
          port: 6379
          password: '{{ secret "/secrets/redis_password" }}'
          database_index: 0

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
          sender: "Authelia <authelia@${domain}>"
          disable_require_tls: false

      authentication_backend:
        ldap:
          implementation: lldap
          address: "ldap://auth:3890"
          base_dn: "${baseDN}"
          user: "uid=admin,ou=people,${baseDN}"
          attributes:
            picture: 'avatarurl'

      definitions:
        user_attributes:
          nextcloud_groups:
            expression: '"nextcloud-admins" in groups ? ["admin"] + groups : groups'
          immich_role:
            expression: '"immich-admins" in groups ? "admin" : "user"'
          litellm_role:
            expression: '"litellm-admins" in groups ? "proxy_admin" : ("litellm-users" in groups ? "internal_user" : "")'

      identity_providers:
        oidc:
          claims_policies:
            nextcloud_userinfo:
              custom_claims:
                nextcloud_groups: {}
            immich_policy:
              id_token:
                - immich_role
              custom_claims:
                immich_role: {}
            litellm_policy:
              id_token:
                - litellm_role
              custom_claims:
                litellm_role: {}
          scopes:
            nextcloud_userinfo:
              claims:
                - nextcloud_groups
            immich_scope:
              claims:
                - immich_role
            litellm_scope:
              claims:
                - litellm_role

          authorization_policies:
            litellm_access:
              default_policy: deny
              rules:
                - policy: two_factor
                  subject:
                    - 'group:litellm-admins'
                    - 'group:litellm-users'
            openwebui_access:
              default_policy: deny
              rules:
                - policy: two_factor
                  subject:
                    - 'group:openwebui-admins'
                    - 'group:openwebui-users'
            nextcloud_access:
              default_policy: deny
              rules:
                - policy: two_factor
                  subject:
                    - 'group:nextcloud-admins'
                    - 'group:nextcloud-users'
            jellyfin_access:
              default_policy: deny
              rules:
                - policy: one_factor
                  subject:
                    - 'group:jellyfin-admins'
                    - 'group:jellyfin-users'
            immich_access:
              default_policy: deny
              rules:
                - policy: two_factor
                  subject:
                    - 'group:immich-admins'
                    - 'group:immich-users'
            vaultwarden_access:
              default_policy: deny
              rules:
                - policy: two_factor
                  subject:
                    - 'group:vaultwarden-users'
            homeassistant_access:
              default_policy: deny
              rules:
                - policy: two_factor
                  subject:
                    - 'group:ha-admins'
                    - 'group:ha-users'
            paperless_access:
              default_policy: deny
              rules:
                - policy: two_factor
                  subject:
                    - 'group:paperless-admins'
                    - 'group:paperless-users'

          jwks:
            - key_id: 'authelia_key'
              key: {{ secret "/secrets/oidc_jwks_key" | mindent 10 "|" | msquote }}
              certificate_chain: {{ secret "/secrets/oidc_jwks_cert" | mindent 10 "|" | msquote }}

          clients:${oidcClients}
    '';
    description = "Generated Authelia configuration.yml";
  };
}
