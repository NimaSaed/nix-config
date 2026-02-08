{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pods.smart-home;
  inherit (config.services.pods) domain mkTraefikLabels;
in
{
  options.services.pods.smart-home = {
    enable = lib.mkEnableOption "Smart Home pod (Scrypted and related services)";

    scrypted = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Scrypted smart home/NVR container in the smart home pod";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "scrypted";
        description = "Subdomain for Scrypted (e.g., scrypted -> scrypted.domain)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.pods._enabledPods = [ "smart-home" ];

    assertions = [
      {
        assertion = config.services.pods.reverse-proxy.enable;
        message = "services.pods.smart-home requires services.pods.reverse-proxy to be enabled (for the reverse_proxy network)";
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
            volumes.scrypted_data = {
              volumeConfig = { };
            };

            pods.smart_home = {
              podConfig = {
                networks = [ networks.reverse_proxy.ref ];
              };
            };

            containers.scrypted = lib.mkIf cfg.scrypted.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStartSec = 120;
              };

              unitConfig = {
                Description = "Scrypted smart home/NVR container";
                After = [ "smart_home-pod.service" ];
              };

              containerConfig = {
                image = "ghcr.io/koush/scrypted";
                pod = pods.smart_home.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "scrypted";
                  port = 10443;
                  scheme = "https";
                  subdomain = cfg.scrypted.subdomain;
                  middlewares = true;
                };

                volumes = [
                  "${volumes.scrypted_data.ref}:/server/volume"
                ];
              };
            };
          };
      };
  };
}
