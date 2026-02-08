{
  config,
  lib,
  pkgs,
  ...
}:

let
  yaml = pkgs.formats.yaml { };
  domain = config.services.pods.domain;
  authCfg = config.services.pods.auth;
  toolsCfg = config.services.pods.tools;
  mediaCfg = config.services.pods.media;
  rpCfg = config.services.pods.reverse-proxy;
  shCfg = config.services.pods.smart-home;
in
{
  options.services.pods.homepage = {
    # =========================================================================
    # Settings
    # =========================================================================
    settingsFile = lib.mkOption {
      type = lib.types.package;
      default = yaml.generate "settings.yaml" {
        title = "Home";
        headerStyle = "clean";
        theme = "dark";
        color = "slate";
        hideVersion = true;
        disableUpdateCheck = true;
        background = {
          image = "https://images.unsplash.com/photo-1502790671504-542ad42d5189?auto=format&fit=crop&w=2560&q=80";
          blur = "sm";
          saturate = 50;
          brightness = 50;
          opacity = 50;
        };
        layout = {
          Services = {
            style = "row";
            columns = 3;
          };
        };
      };
      description = "Generated settings.yaml file";
    };

    # =========================================================================
    # Services
    # =========================================================================
    servicesFile = lib.mkOption {
      type = lib.types.package;
      default = yaml.generate "services.yaml" [
        {
          Services = lib.flatten [
            # Core Infrastructure Services - always enabled
            [
              {
                Traefik = {
                  icon = "sh-traefik";
                  href = "https://${rpCfg.subdomain}.${domain}/";
                };
              }
              {
                Authelia = {
                  icon = "sh-authelia";
                  href = "https://${authCfg.authelia.subdomain}.${domain}/";
                };
              }
              {
                lldap = {
                  icon = "sh-lldap-light";
                  href = "https://${authCfg.lldap.subdomain}.${domain}/";
                };
              }
            ]

            # Optional Managed Containers - conditional on enable flags
            (lib.optionals mediaCfg.jellyfin.enable [
              {
                Jellyfin = {
                  icon = "sh-jellyfin";
                  href = "https://${mediaCfg.jellyfin.subdomain}.${domain}/sso/OID/start/authelia";
                  description = "Movies, TV shows and Music";
                };
              }
            ])

            (lib.optionals shCfg.scrypted.enable [
              {
                Scrypted = {
                  icon = "sh-scrypted";
                  href = "https://${shCfg.scrypted.subdomain}.${domain}/";
                };
              }
            ])

            (lib.optionals toolsCfg.itTools.enable [
              {
                "IT Tools" = {
                  icon = "it-tools";
                  href = "https://${toolsCfg.itTools.subdomain}.${domain}/";
                };
              }
            ])

            (lib.optionals toolsCfg.dozzle.enable [
              {
                Dozzle = {
                  icon = "sh-dozzle";
                  href = "https://${toolsCfg.dozzle.subdomain}.${domain}/";
                };
              }
            ])

            # Future Managed Containers - commented out until pod modules exist
            # TODO: Uncomment when respective pod modules are created
            # (lib.optionals cloudCfg.nextcloud.enable [
            #   {
            #     Nextcloud = {
            #       icon = "sh-nextcloud";
            #       href = "https://${cloudCfg.nextcloud.subdomain}.${domain}/";
            #       description = "iCloud replacement";
            #     };
            #   }
            # ])
            #
            # (lib.optionals mediaCfg.jellyseerr.enable [
            #   {
            #     Jellyseerr = {
            #       icon = "sh-jellyseerr";
            #       href = "https://${mediaCfg.jellyseerr.subdomain}.${domain}";
            #     };
            #   }
            # ])
            #
            # (lib.optionals mediaCfg.sonarr.enable [
            #   {
            #     Sonarr = {
            #       icon = "sh-sonarr";
            #       href = "https://${mediaCfg.sonarr.subdomain}.${domain}/";
            #     };
            #   }
            # ])
            #
            # (lib.optionals mediaCfg.radarr.enable [
            #   {
            #     Radarr = {
            #       icon = "sh-radarr";
            #       href = "https://${mediaCfg.radarr.subdomain}.${domain}/";
            #     };
            #   }
            # ])
            #
            # (lib.optionals mediaCfg.nzbget.enable [
            #   {
            #     Nzbget = {
            #       icon = "sh-nzbget";
            #       href = "https://${mediaCfg.nzbget.subdomain}.${domain}/";
            #     };
            #   }
            # ])
            #
            # (lib.optionals toolsCfg.changeDetection.enable [
            #   {
            #     "Change Detection" = {
            #       icon = "sh-changedetection";
            #       href = "https://${toolsCfg.changeDetection.subdomain}.${domain}/";
            #     };
            #   }
            # ])

            # Truly External Services - always included
            [
              {
                Unifi = {
                  icon = "sh-ubiquiti-unifi";
                  href = "https://unifi.ui.com/";
                };
              }
            ]
          ];
        }
      ];
      description = "Generated services.yaml file";
    };

    # =========================================================================
    # Bookmarks
    # =========================================================================
    bookmarksFile = lib.mkOption {
      type = lib.types.package;
      default = yaml.generate "bookmarks.yaml" [ ];
      description = "Generated bookmarks.yaml file";
    };

    # =========================================================================
    # Widgets
    # =========================================================================
    widgetsFile = lib.mkOption {
      type = lib.types.package;
      default = yaml.generate "widgets.yaml" [ ];
      description = "Generated widgets.yaml file";
    };

    # =========================================================================
    # Docker
    # =========================================================================
    dockerFile = lib.mkOption {
      type = lib.types.package;
      default = yaml.generate "docker.yaml" { };
      description = "Generated docker.yaml file";
    };

    # =========================================================================
    # Kubernetes
    # =========================================================================
    kubernetesFile = lib.mkOption {
      type = lib.types.package;
      default = yaml.generate "kubernetes.yaml" { };
      description = "Generated kubernetes.yaml file";
    };

    # =========================================================================
    # Proxmox
    # =========================================================================
    proxmoxFile = lib.mkOption {
      type = lib.types.package;
      default = yaml.generate "proxmox.yaml" { };
      description = "Generated proxmox.yaml file";
    };

    # =========================================================================
    # Custom CSS
    # =========================================================================
    customCssFile = lib.mkOption {
      type = lib.types.package;
      default = pkgs.writeText "custom.css" ''
        #footer {
          display: none;
        }
      '';
      description = "Generated custom.css file";
    };

    # =========================================================================
    # Custom JS
    # =========================================================================
    customJsFile = lib.mkOption {
      type = lib.types.package;
      default = pkgs.writeText "custom.js" "";
      description = "Generated custom.js file";
    };
  };
}
