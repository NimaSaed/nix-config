{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pods.media;
  nixosConfig = config;
  inherit (config.services.pods) domain mkTraefikLabels;
in
{
  imports = [
    ./container-configs/nzbget.nix
  ];

  options.services.pods.media = {
    enable = lib.mkEnableOption "Media pod (Jellyfin and related services)";

    jellyfin = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Jellyfin media server container in the media pod";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "jellyfin";
        description = "Subdomain for Jellyfin (e.g., jellyfin -> jellyfin.domain)";
      };
    };

    sonarr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable sonarr container in the media pod";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "sonarr";
        description = "Subdomain for sonarr (e.g., sonarr -> sonarr.domain)";
      };
    };

    radarr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable radarr container in the media pod";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "radarr";
        description = "Subdomain for radarr (e.g., radarr -> radarr.domain)";
      };
    };

    nzbget = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable nzbget container in the media pod";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "nzbget";
        description = "Subdomain for nzbget (e.g., nzbget -> nzbget.domain)";
      };
    };

    jellyseerr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable jellyseerr container in the media pod";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "jellyseerr";
        description = "Subdomain for jellyseerr (e.g., jellyseerr -> jellyseerr.domain)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.pods._enabledPods = [ "media" ];

    assertions = [
      {
        assertion = builtins.elem "reverse-proxy" config.services.pods._enabledPods;
        message = "services.pods.media requires Traefik (reverse-proxy) to be configured";
      }
    ];

    home-manager.users.poddy =
      { pkgs, config, ... }:
      {
        virtualisation.quadlet =
          let
            nzbgetSecretsPath = nixosConfig.sops.templates."nzbget-secrets".path;
            nzbgetConfigPath = nixosConfig.sops.templates."nzbget.conf".path;
            nzbgetInitScript = pkgs.writeShellScript "01-deploy-config" ''
              echo "[nix-init] Deploying declarative nzbget.conf..."
              cp /defaults/nzbget.conf /config/nzbget.conf
              chmod 644 /config/nzbget.conf
              echo "[nix-init] nzbget.conf deployed successfully"
            '';
            inherit (config.virtualisation.quadlet) networks pods volumes;
          in
          {
            volumes.jellyfin_config = {
              volumeConfig = { };
            };
            volumes.jellyfin_cache = {
              volumeConfig = { };
            };

            volumes.sonarr = {
              volumeConfig = { };
            };

            volumes.radarr = {
              volumeConfig = { };
            };

            volumes.nzbget = {
              volumeConfig = { };
            };

            volumes.jellyseerr = {
              volumeConfig = { };
            };

            pods.media = {
              podConfig = {
                networks = [ networks.reverse_proxy.ref ];
                userns = "keep-id:uid=1001,gid=1001";
              };
            };

            containers.jellyfin = lib.mkIf cfg.jellyfin.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Jellyfin media server container";
                After = [ pods.media.ref ];
              };

              containerConfig = {
                image = "docker.io/jellyfin/jellyfin:latest";
                pod = pods.media.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "jellyfin";
                  port = 8096;
                  subdomain = cfg.jellyfin.subdomain;
                };

                volumes = [
                  "${volumes.jellyfin_cache.ref}:/cache"
                  "${volumes.jellyfin_config.ref}:/config"
                  "/data/media:/media:ro"
                ];

                devices = [ "/dev/dri:/dev/dri" ];
              };
            };
            containers.sonarr = lib.mkIf cfg.sonarr.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Sonarr container";
                After = [ pods.media.ref ];
              };

              containerConfig = {
                image = "lscr.io/linuxserver/sonarr:latest";
                pod = pods.media.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "sonarr";
                  port = 8989;
                  subdomain = cfg.sonarr.subdomain;
                };

                environments = {
                  TZ = "Europe/Amsterdam";
                };

                volumes = [
                  "${volumes.sonarr.ref}:/config"
                  "/data/media:/media:rw"
                ];
              };
            };

            containers.radarr = lib.mkIf cfg.radarr.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Radarr container";
                After = [ pods.media.ref ];
              };

              containerConfig = {
                image = "lscr.io/linuxserver/radarr:latest";
                pod = pods.media.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "radarr";
                  port = 7878;
                  subdomain = cfg.radarr.subdomain;
                };

                environments = {
                  TZ = "Europe/Amsterdam";
                };

                volumes = [
                  "${volumes.radarr.ref}:/config"
                  "/data/media:/media:rw"
                ];
              };
            };

            containers.nzbget = lib.mkIf cfg.nzbget.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "NZBGet container";
                After = [ pods.media.ref ];
              };

              containerConfig = {
                image = "lscr.io/linuxserver/nzbget:latest";
                pod = pods.media.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "nzbget";
                  port = 6789;
                  subdomain = cfg.nzbget.subdomain;
                };

                environments = {
                  TZ = "Europe/Amsterdam";
                };

                environmentFiles = [ nzbgetSecretsPath ];

                volumes = [
                  "${volumes.nzbget.ref}:/config"
                  "${nzbgetConfigPath}:/defaults/nzbget.conf:ro"
                  "${nzbgetInitScript}:/custom-cont-init.d/01-deploy-config:ro"
                  "/data/media:/media:rw"
                ];
              };
            };

            containers.jellyseerr = lib.mkIf cfg.jellyseerr.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Jellyseerr container";
                After = [ pods.media.ref ];
              };

              containerConfig = {
                image = "docker.io/fallenbagel/jellyseerr:latest";
                pod = pods.media.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "jellyseerr";
                  port = 5055;
                  subdomain = cfg.jellyseerr.subdomain;
                };

                environments = {
                  TZ = "Europe/Amsterdam";
                  LOG_LEVEL = "debug";
                };

                volumes = [
                  "${volumes.jellyseerr.ref}:/app/config"
                ];
              };
            };
          };
      };

    # NZBGet secrets - password for web UI and news server credentials
    sops.secrets = lib.genAttrs [
      "nzbget/username"
      "nzbget/password"
      "nzbget/server_host"
      "nzbget/server_username"
      "nzbget/server_password"
    ] (_: {
      owner = "poddy";
      group = "poddy";
    });

    sops.templates."nzbget-secrets" = {
      content = ''
        NZBGET_USER=${config.sops.placeholder."nzbget/username"}
        NZBGET_PASS=${config.sops.placeholder."nzbget/password"}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };

    sops.templates."nzbget.conf" = {
      content = cfg.nzbget.configContent;
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };
  };
}
