{
  config,
  lib,
  ...
}:

let
  cfg = config.services.pods.immich;
  nixosConfig = config;
  inherit (config.services.pods) domain mkTraefikLabels;
in
{
  imports = [
    ./container-configs/immich.nix
  ];

  options.services.pods.immich = {
    enable = lib.mkEnableOption "Immich photo library pod";

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "photos";
      description = "Subdomain for Immich (e.g., photos -> photos.example.com)";
    };

    machinelearning = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable ML container for facial recognition and CLIP semantic search";
      };

      openvino = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Enable Intel iGPU acceleration via OpenVINO.
            Uses the -openvino image tag and mounts /dev/dri.
            The poddy user already has render+video groups.
            Note: integrated GPUs are more prone to issues than discrete GPUs.
            Start with CPU-only (false) and enable if indexing is too slow.
          '';
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.pods._enabledPods = [ "immich" ];

    assertions = [
      {
        assertion = builtins.elem "reverse-proxy" config.services.pods._enabledPods;
        message = "services.pods.immich requires Traefik (reverse-proxy) to be configured";
      }
      {
        assertion = builtins.elem "auth" config.services.pods._enabledPods;
        message = "services.pods.immich requires Authelia (auth) for OIDC authentication";
      }
    ];

    home-manager.users.poddy =
      { pkgs, config, ... }:
      {
        virtualisation.quadlet =
          let
            inherit (config.virtualisation.quadlet) networks pods volumes;
            mlImage =
              if cfg.machinelearning.openvino.enable then
                "ghcr.io/immich-app/immich-machine-learning:release-openvino"
              else
                "ghcr.io/immich-app/immich-machine-learning:release";
          in
          {
            # Named volumes for persistent data (all on /data/containers ZFS dataset)
            volumes.immich_db = {
              volumeConfig = { };
            };
            volumes.immich_model_cache = {
              volumeConfig = { };
            };
            volumes.immich_photo = {
              volumeConfig = { };
            };

            # Pod definition — joins the reverse_proxy network for Traefik discovery
            pods.immich = {
              podConfig = {
                networks = [ networks.reverse_proxy.ref ];
              };
            };

            # Container 1: PostgreSQL with VectorChord extension (vector similarity search)
            containers.immich-db = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Immich PostgreSQL + VectorChord database container";
                After = [ pods.immich.ref ];
              };

              containerConfig = {
                image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0";
                pod = pods.immich.ref;
                # Pin to digest — do not use autoUpdate for DB to prevent unexpected schema changes
                autoUpdate = "registry";

                environments = {
                  TZ = "Europe/Amsterdam";
                  POSTGRES_USER = "immich";
                  POSTGRES_DB = "immich";
                  # Enable page-level checksums at initdb time (cannot be changed after init)
                  POSTGRES_INITDB_ARGS = "--data-checksums";
                };

                environmentFiles = [ nixosConfig.sops.templates."immich-db-secrets".path ];

                volumes = [
                  "${volumes.immich_db.ref}:/var/lib/postgresql/data"
                ];
              };
            };

            # Container 2: Valkey (Redis-compatible) cache
            containers.immich-redis = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Immich Valkey cache container";
                After = [ pods.immich.ref ];
              };

              containerConfig = {
                image = "docker.io/valkey/valkey:9";
                pod = pods.immich.ref;
                autoUpdate = "registry";
              };
            };

            # Container 3: Immich server (main API + web UI)
            containers.immich-server = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Immich server container";
                After = [
                  pods.immich.ref
                  "immich-db.service"
                  "immich-redis.service"
                ];
              };

              containerConfig = {
                image = "ghcr.io/immich-app/immich-server:release";
                pod = pods.immich.ref;
                autoUpdate = "registry";

                labels = mkTraefikLabels {
                  name = "immich";
                  port = 2283;
                  subdomain = cfg.subdomain;
                  # No forward auth middleware — Immich handles auth itself via OIDC
                  middlewares = false;
                };

                environments = {
                  TZ = "Europe/Amsterdam";
                  # Database connection (pod-internal via 127.0.0.1)
                  DB_HOSTNAME = "127.0.0.1";
                  DB_USERNAME = "immich";
                  DB_DATABASE_NAME = "immich";
                  # Redis connection (pod-internal via 127.0.0.1)
                  REDIS_HOSTNAME = "127.0.0.1";
                  # System config file — pre-configures OAuth and ML URL declaratively
                  IMMICH_CONFIG_FILE = "/etc/immich/immich.json";
                };

                environmentFiles = [ nixosConfig.sops.templates."immich-db-secrets".path ];

                volumes = [
                  "${volumes.immich_photo.ref}:/data"
                  "${nixosConfig.services.pods.immich._configFile}:/etc/immich/immich.json:ro"
                ];
              };
            };

            # Container 4: Immich machine learning (facial recognition + CLIP search)
            containers.immich-ml = lib.mkIf cfg.machinelearning.enable {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStopSec = 70;
              };

              unitConfig = {
                Description = "Immich machine learning inference container";
                After = [ pods.immich.ref ];
              };

              containerConfig = {
                image = mlImage;
                pod = pods.immich.ref;
                autoUpdate = "registry";

                environments = {
                  TZ = "Europe/Amsterdam";
                };

                volumes = [
                  "${volumes.immich_model_cache.ref}:/cache"
                ];

                # Mount Intel iGPU for OpenVINO acceleration (optional)
                devices = lib.optionals cfg.machinelearning.openvino.enable [
                  "/dev/dri:/dev/dri"
                ];
              };
            };
          };
      };

    # Secret management using sops-nix
    sops.secrets =
      lib.genAttrs
        [
          "immich/db_password"
          "immich/oauth_client_secret"
        ]
        (_: {
          owner = "poddy";
          group = "poddy";
        });

    # Database password (shared between immich-db and immich-server)
    sops.templates."immich-db-secrets" = {
      content = ''
        POSTGRES_PASSWORD=${config.sops.placeholder."immich/db_password"}
        DB_PASSWORD=${config.sops.placeholder."immich/db_password"}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };
  };
}

# Post-deployment notes (run AFTER first boot):
#
# 1. Wait for database initialization and server startup:
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman logs immich-db
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman logs immich-server
#
# 2. Visit https://photos.<domain> and create the initial admin account.
#    (IMMICH_CONFIG_FILE pre-configures OAuth — the "Login with Authelia"
#    button will appear automatically on the login page after admin creation.)
#
# 3. ML models are downloaded on first inference (~1GB). Check progress:
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman logs immich-ml
#
# 4. Verify pod status:
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman pod ps
#    sudo -u poddy XDG_RUNTIME_DIR=/run/user/1001 podman ps
#
# 5. To enable OpenVINO (Intel iGPU) acceleration after testing CPU-only:
#    Set services.pods.immich.machinelearning.openvino.enable = true;
#    Then nixos-rebuild switch (restarts immich-ml with -openvino image)
