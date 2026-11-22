{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pods.reverse-proxy;
  inherit (config.services.pods) domain mkTraefikRoute;
  nixosConfig = config;

  quadlet = config.home-manager.users.poddy.virtualisation.quadlet;

  podNames = lib.mapAttrs' (
    name: pod:
    lib.nameValuePair pod.ref (if pod.podConfig.name != null then pod.podConfig.name else name)
  ) quadlet.pods;

  containerHost =
    name: container:
    let
      inherit (container.containerConfig) pod;
    in
    if pod != null then
      podNames.${pod} or (lib.removeSuffix ".pod" pod)
    else if container.containerConfig.name != null then
      container.containerConfig.name
    else
      name;

  routeSources =
    lib.mapAttrsToList (name: container: {
      host = containerHost name container;
      inherit (container) routes;
    }) (lib.filterAttrs (_: container: container.routes != { }) quadlet.containers)
    ++ lib.mapAttrsToList (_: backend: { inherit (backend) host routes; }) cfg.backends;

  splitIndex =
    segment:
    let
      indexed = builtins.match "(.+)\\[([0-9]+)]" segment;
    in
    if indexed == null then [ segment ] else indexed;

  toTree =
    routes:
    let
      entries = lib.mapAttrsToList (key: value: {
        path = lib.concatMap splitIndex (lib.splitString "." (lib.removePrefix "traefik." key));
        inherit value;
      }) routes;
      shortestFirst = lib.sort (a: b: builtins.length a.path < builtins.length b.path) entries;
    in
    lib.foldl' (
      tree: entry: lib.recursiveUpdate tree (lib.setAttrByPath entry.path entry.value)
    ) { } shortestFirst;

  fixRouter =
    router:
    if (router.tls or null) == "true" then
      router // { tls = { }; }
    else if (router.tls or null) == "false" then
      removeAttrs router [ "tls" ]
    else
      router;

  fixService =
    protocol: host: service:
    let
      server = service.loadbalancer.server or null;
    in
    if server == null then
      service
    else
      service
      // {
        loadbalancer = removeAttrs service.loadbalancer [ "server" ] // {
          servers = [
            (
              if protocol == "http" then
                { url = "${server.scheme or "http"}://${host}:${server.port}"; }
              else
                { address = "${host}:${server.port}"; }
            )
          ];
        };
      };

  sourceToConfig =
    source:
    lib.mapAttrs (
      protocol: section:
      section
      // lib.optionalAttrs (section ? routers) { routers = lib.mapAttrs (_: fixRouter) section.routers; }
      // lib.optionalAttrs (section ? services) {
        services = lib.mapAttrs (_: fixService protocol source.host) section.services;
      }
    ) (toTree source.routes);

  sourceConfigs = map sourceToConfig routeSources;

  definedNames =
    sourceConfig:
    lib.concatLists (
      lib.mapAttrsToList (
        protocol: section:
        lib.concatLists (
          lib.mapAttrsToList (
            kind: items: map (item: "${protocol}.${kind}.${item}") (lib.attrNames items)
          ) section
        )
      ) sourceConfig
    );

  allNames = lib.concatMap definedNames sourceConfigs;
  duplicateNames = lib.unique (
    lib.filter (name: lib.count (other: other == name) allNames > 1) allNames
  );

  indexedToLists =
    value:
    if builtins.isAttrs value then
      let
        names = lib.attrNames value;
      in
      if names != [ ] && lib.all (name: builtins.match "[0-9]+" name != null) names then
        map (name: indexedToLists value.${name}) names
      else
        lib.mapAttrs (_: indexedToLists) value
    else
      value;

  dynamicConfig = indexedToLists (lib.foldl' lib.recursiveUpdate { } sourceConfigs);

  routesType = lib.types.attrsOf lib.types.str;

  containerRoutesModule = {
    options.virtualisation.quadlet.containers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.routes = lib.mkOption {
            type = routesType;
            default = { };
            description = "Traefik routes to this container, built with mkTraefikRoute";
          };
        }
      );
    };
  };
in
{
  options.services.pods.reverse-proxy = {
    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "traefik";
      description = "Subdomain for Traefik dashboard";
    };
    useAcmeStaging = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use Let's Encrypt staging server (for testing, avoids rate limits)";
    };
    backends = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            host = lib.mkOption {
              type = lib.types.str;
              description = "Address Traefik reaches this backend on";
            };
            routes = lib.mkOption {
              type = routesType;
              default = { };
              description = "Traefik routes to this backend, built with mkTraefikRoute";
            };
          };
        }
      );
      default = { };
      description = "Backends that are not poddy containers, such as VMs and host services";
    };
  };

  config = {
    services.pods._enabledPods = [ "reverse-proxy" ];

    assertions = [
      {
        assertion = duplicateNames == [ ];
        message = "Traefik routes defined more than once: ${lib.concatStringsSep ", " duplicateNames}";
      }
    ];

    # mode != "symlink" makes NixOS copy the file: a /nix/store symlink would
    # not resolve inside the Traefik container.
    environment.etc."traefik/dynamic/routes.yml" = {
      mode = "0444";
      source = (pkgs.formats.yaml { }).generate "traefik-routes.yml" dynamicConfig;
    };

    # Declare secrets this module needs
    sops.secrets =
      lib.genAttrs
        [
          "reverse-proxy/acme_email"
          "reverse-proxy/desec_token"
        ]
        (_: {
          owner = "poddy";
          group = "poddy";
        });

    networking.firewall = {
      allowedTCPPorts = [
        80
        443
      ];
    };

    # The Traefik container bind-mounts this directory; rootless podman cannot
    # create it under /etc, so it must exist even when no module drops a file in it
    systemd.tmpfiles.rules = [
      "d /etc/traefik/dynamic 0755 root root - -"
    ];

    home-manager.users.poddy =
      { pkgs, config, ... }:
      {
        imports = [ containerRoutesModule ];

        virtualisation.quadlet =
          let
            secretsPath = nixosConfig.sops.templates."traefik-secrets".path;
            inherit (config.virtualisation.quadlet) networks pods volumes;
          in
          {
            volumes.traefik = {
              volumeConfig = { };
            };
            networks.reverse_proxy = {
              networkConfig = {
                name = "reverse_proxy";
              };
            };

            pods.reverse_proxy = {
              podConfig = {
                networks = [ networks.reverse_proxy.ref ];
                publishPorts = [
                  "80:80"
                  "443:443"
                  "8080:8080"
                  "636:636"
                ];
              };
            };

            containers.reverse-proxy-traefik = {
              autoStart = true;

              serviceConfig = {
                Restart = "always";
                TimeoutStartSec = 120;
              };

              unitConfig = {
                Description = "Traefik reverse proxy container";
                After = [ pods.reverse_proxy.ref ];
              };

              routes = mkTraefikRoute {
                name = "traefik";
                port = 8080;
                subdomain = cfg.subdomain;
                middlewares = true;
                extraRouteConfig = name: {
                  # Override service to use Traefik's internal dashboard API
                  "traefik.http.routers.${name}.service" = "api@internal";
                };
              };

              containerConfig = {
                image = "docker.io/library/traefik:latest";
                pod = pods.reverse_proxy.ref;
                autoUpdate = "registry";

                volumes = [
                  "${volumes.traefik.ref}:/data"
                  "/etc/traefik/dynamic:/etc/traefik/dynamic:ro"
                ];

                environmentFiles = [ secretsPath ];

                environments = {
                  TRAEFIK_LOG_LEVEL = "INFO";
                  # Routes are rendered into this directory via environment.etc
                  TRAEFIK_PROVIDERS_FILE_DIRECTORY = "/etc/traefik/dynamic";
                  TRAEFIK_PROVIDERS_FILE_WATCH = "true";
                  TRAEFIK_API = "true";
                  TRAEFIK_API_DASHBOARD = "true";
                  TRAEFIK_API_INSECURE = "true";
                  TRAEFIK_ENTRYPOINTS_WEB_ADDRESS = ":80";
                  TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS = ":443";
                  TRAEFIK_ENTRYPOINTS_LLDAPSECURE_ADDRESS = ":636";
                  TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_TO = "websecure";
                  TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_SCHEME = "https";
                  TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE = "true";
                  TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE_PROVIDER = "desec";
                  TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE_RESOLVERS = "45.54.76.1:53,157.53.224.1:53";
                  TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_STORAGE = "/data/acme.json";
                  TRAEFIK_SERVERSTRANSPORT_INSECURESKIPVERIFY = "true";
                }
                // lib.optionalAttrs cfg.useAcmeStaging {
                  TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_CASERVER = "https://acme-staging-v02.api.letsencrypt.org/directory";
                };
              };
            };
          };
      };

    sops.templates."traefik-secrets" = {
      content = ''
        TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL=${
          config.sops.placeholder."reverse-proxy/acme_email"
        }
        DESEC_TOKEN=${config.sops.placeholder."reverse-proxy/desec_token"}
      '';
      owner = "poddy";
      group = "poddy";
      mode = "0400";
    };
  };
}
