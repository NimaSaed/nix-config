{
  config,
  lib,
  ...
}:

let
  cfg = config.services.pods.immich;
  inherit (config.services.pods) domain;
  authCfg = config.services.pods.auth;
in
{
  options.services.pods.immich._configFile = lib.mkOption {
    type = lib.types.path;
    internal = true;
    default = config.sops.templates."immich-config.json".path;
    description = "Path to the rendered immich-config.json sops template";
  };

  config = lib.mkIf cfg.enable {
    # Immich system configuration file (IMMICH_CONFIG_FILE).
    # Declaratively configures OAuth/OIDC and ML backend URL, avoiding clickops.
    # Uses builtins.toJSON for safe JSON generation — sops placeholder is
    # injected as a string value before JSON serialization.
    sops.templates."immich-config.json" = {
      content = builtins.toJSON {
        oauth = {
          enabled = true;
          issuerUrl = "https://${authCfg.authelia.subdomain}.${domain}/.well-known/openid-configuration";
          clientId = "immich";
          clientSecret = config.sops.placeholder."immich/oauth_client_secret";
          scope = "openid email profile immich_scope";
          autoRegister = true;
          autoLaunch = true;
          buttonText = "Login with Authelia";
          tokenEndpointAuthMethod = "client_secret_post";
          roleClaim = "immich_role";
        };
        passwordLogin = {
          # Disable email/password login — enforce OIDC-only via Authelia
          enabled = false;
        };
        machineLearning = {
          # ML container shares the pod network namespace — reach it via localhost
          urls = [ "http://127.0.0.1:3003" ];
        };
      };
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };
  };
}
