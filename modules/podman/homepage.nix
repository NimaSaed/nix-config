{ lib, pkgs, ... }:

let
  yaml = pkgs.formats.yaml { };
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
          Services = [
            { Jellyfin = { icon = "sh-jellyfin"; href = "https://media.nmsd.xyz/sso/OID/start/authelia"; description = "Movies, TV shows and Music"; }; }
            { Nextcloud = { icon = "sh-nextcloud"; href = "https://cloud.nmsd.xyz/"; description = "iCloud replacement"; }; }
            { lldap = { icon = "sh-lldap-light"; href = "https://lldap.nmsd.xyz/"; }; }
            { "Server 1" = { icon = "sh-fedora"; href = "https://srv1.nmsd.xyz/"; }; }
            { Scrypted = { icon = "sh-scrypted"; href = "https://scrypted.nmsd.xyz/"; }; }
            { "IT Tools" = { icon = "it-tools"; href = "https://tools.nmsd.xyz/"; }; }
            { Authelia = { icon = "sh-authelia"; href = "https://auth.nmsd.xyz/"; }; }
            { Unifi = { icon = "sh-ubiquiti-unifi"; href = "https://unifi.ui.com/"; }; }
            { Traefik = { icon = "sh-traefik"; href = "https://traefik.nmsd.xyz/"; }; }
            { Jellyseerr = { icon = "sh-jellyseerr"; href = "https://jellyseerr.nmsd.xyz"; }; }
            { Sonarr = { icon = "sh-sonarr"; href = "https://sonarr.nmsd.xyz/"; }; }
            { Radarr = { icon = "sh-radarr"; href = "https://radarr.nmsd.xyz/"; }; }
            { Nzbget = { icon = "sh-nzbget"; href = "https://nzbget.nmsd.xyz/"; }; }
            { "Change Detection" = { icon = "sh-changedetection"; href = "https://changedetection.nmsd.xyz/"; }; }
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
