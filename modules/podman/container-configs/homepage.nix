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
  nextcloudCfg = config.services.pods.nextcloud;
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
        layout = [
          { Media = { style = "row"; columns = 3; }; }
          { Storage = { style = "row"; columns = 3; }; }
          { Tools = { style = "row"; columns = 3; }; }
          { Infrastructure = { style = "row"; columns = 3; }; }
        ];
      };
      description = "Generated settings.yaml file";
    };

    # =========================================================================
    # Services
    # =========================================================================
    servicesFile = lib.mkOption {
      type = lib.types.package;
      default = yaml.generate "services.yaml" [
        # -----------------------------------------------------------------------
        # Media
        # -----------------------------------------------------------------------
        {
          Media = lib.flatten [
            (lib.optionals mediaCfg.jellyfin.enable [
              {
                Jellyfin = {
                  icon = "sh-jellyfin";
                  href = "https://${mediaCfg.jellyfin.subdomain}.${domain}/sso/OID/start/authelia";
                  description = "Movies, TV shows and Music";
                };
              }
            ])
            (lib.optionals mediaCfg.jellyseerr.enable [
              {
                Jellyseerr = {
                  icon = "sh-jellyseerr";
                  href = "https://${mediaCfg.jellyseerr.subdomain}.${domain}";
                  description = "Media request and discovery manager";
                };
              }
            ])
            (lib.optionals mediaCfg.sonarr.enable [
              {
                Sonarr = {
                  icon = "sh-sonarr";
                  href = "https://${mediaCfg.sonarr.subdomain}.${domain}/";
                  description = "Automated TV show download manager";
                };
              }
            ])
            (lib.optionals mediaCfg.radarr.enable [
              {
                Radarr = {
                  icon = "sh-radarr";
                  href = "https://${mediaCfg.radarr.subdomain}.${domain}/";
                  description = "Automated movie download manager";
                };
              }
            ])
            (lib.optionals mediaCfg.nzbget.enable [
              {
                Nzbget = {
                  icon = "sh-nzbget";
                  href = "https://${mediaCfg.nzbget.subdomain}.${domain}/";
                  description = "Usenet binary downloader client";
                };
              }
            ])
          ];
        }

        # -----------------------------------------------------------------------
        # Storage
        # -----------------------------------------------------------------------
        {
          Storage = lib.flatten [
            (lib.optionals nextcloudCfg.enable [
              {
                Nextcloud = {
                  icon = "sh-nextcloud";
                  href = "https://${nextcloudCfg.subdomain}.${domain}/apps/oidc_login/oidc";
                  description = "Files, calendar, and collaboration suite";
                };
              }
            ])
          ];
        }

        # -----------------------------------------------------------------------
        # Tools
        # -----------------------------------------------------------------------
        {
          Tools = lib.flatten [
            (lib.optionals toolsCfg.itTools.enable [
              {
                "IT Tools" = {
                  icon = "it-tools";
                  href = "https://${toolsCfg.itTools.subdomain}.${domain}/";
                  description = "Developer and IT utility toolkit";
                };
              }
            ])
            (lib.optionals toolsCfg.dozzle.enable [
              {
                Dozzle = {
                  icon = "sh-dozzle";
                  href = "https://${toolsCfg.dozzle.subdomain}.${domain}/";
                  description = "Real-time Docker log viewer";
                };
              }
            ])
            (lib.optionals shCfg.scrypted.enable [
              {
                Scrypted = {
                  icon = "sh-scrypted";
                  href = "https://${shCfg.scrypted.subdomain}.${domain}/";
                  description = "Smart home camera management hub";
                };
              }
            ])
            # (lib.optionals toolsCfg.changeDetection.enable [
            #   {
            #     "Change Detection" = {
            #       icon = "sh-changedetection";
            #       href = "https://${toolsCfg.changeDetection.subdomain}.${domain}/";
            #     };
            #   }
            # ])
          ];
        }

        # -----------------------------------------------------------------------
        # Infrastructure
        # -----------------------------------------------------------------------
        {
          Infrastructure = lib.flatten [
            [
              {
                Traefik = {
                  icon = "sh-traefik";
                  href = "https://${rpCfg.subdomain}.${domain}/";
                  description = "Reverse proxy and load balancer";
                };
              }
              {
                Authelia = {
                  icon = "sh-authelia";
                  href = "https://${authCfg.authelia.subdomain}.${domain}/";
                  description = "Single sign-on authentication portal";
                };
              }
              {
                lldap = {
                  icon = "sh-lldap-light";
                  href = "https://${authCfg.lldap.subdomain}.${domain}/";
                  description = "Lightweight LDAP user directory";
                };
              }
              {
                Unifi = {
                  icon = "sh-ubiquiti-unifi";
                  href = "https://unifi.ui.com/";
                  description = "Ubiquiti network device management";
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
