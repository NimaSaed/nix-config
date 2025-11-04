{ config, lib, pkgs, ... }:

{
  # ============================================================================
  # Traefik Reverse Proxy - Rootless Podman Container
  # ============================================================================
  # This module creates systemd user services for the Traefik reverse proxy
  # running in a rootless Podman pod. The configuration mirrors the systemd
  # units from pod-reverse_proxy.service and container-traefik.service.
  #
  # REQUIREMENTS:
  # - poddy user must exist (import ../users/poddy)
  # - sops-nix configured with Namecheap secrets
  # - /data/traefik/acme.json must exist with 600 permissions
  #
  # SECRETS (via sops-nix):
  # - namecheap_email
  # - namecheap_api_user
  # - namecheap_api_key

  # ============================================================================
  # Pod Service: reverse_proxy
  # ============================================================================
  # Creates a Podman pod with published ports for HTTP/HTTPS/Dashboard/LDAPS

  systemd.user.services.pod-reverse_proxy = {
    description = "Podman pod-reverse_proxy";
    documentation = [ "man:podman-generate-systemd(1)" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    requires = [ "%t/containers" ];
    wantedBy = [ "default.target" ];

    serviceConfig = {
      Environment = "PODMAN_SYSTEMD_UNIT=%n";
      Restart = "always";
      TimeoutStopSec = 70;
      Type = "forking";
      PIDFile = "%t/pod-reverse_proxy.pid";

      ExecStartPre = "${pkgs.podman}/bin/podman pod create "
        + "--infra-conmon-pidfile %t/pod-reverse_proxy.pid "
        + "--pod-id-file %t/pod-reverse_proxy.pod-id " + "--exit-policy=stop "
        + "--name reverse_proxy " + "--network reverse_proxy "
        + "--publish 80:80/tcp " + "--publish 443:443/tcp "
        + "--publish 8080:8080/tcp " + "--publish 636:636/tcp " + "--replace";

      ExecStart = "${pkgs.podman}/bin/podman pod start "
        + "--pod-id-file %t/pod-reverse_proxy.pod-id";

      ExecStop = "${pkgs.podman}/bin/podman pod stop " + "--ignore "
        + "--pod-id-file %t/pod-reverse_proxy.pod-id " + "-t 10";

      ExecStopPost = "${pkgs.podman}/bin/podman pod rm " + "--ignore " + "-f "
        + "--pod-id-file %t/pod-reverse_proxy.pod-id";
    };
  };

  # ============================================================================
  # Container Service: traefik
  # ============================================================================
  # Traefik reverse proxy container with:
  # - Namecheap DNS challenge for Let's Encrypt
  # - Automatic HTTPS redirects
  # - Dashboard on traefik.nmsd.xyz
  # - Cockpit proxy on srv1.nmsd.xyz

  systemd.user.services.container-traefik = {
    description = "Podman container-traefik";
    documentation = [ "man:podman-generate-systemd(1)" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "pod-reverse_proxy.service" ];
    bindsTo = [ "pod-reverse_proxy.service" ];
    requires = [ "%t/containers" ];
    wantedBy = [ "default.target" ];

    serviceConfig = {
      Environment = "PODMAN_SYSTEMD_UNIT=%n";
      Restart = "always";
      TimeoutStopSec = 70;
      Type = "notify";
      NotifyAccess = "all";

      # Load secrets as environment variables
      # These files are created by sops-nix at /run/user/$(id -u poddy)/secrets/
      EnvironmentFile = [ "${config.sops.templates."traefik-secrets".path}" ];

      ExecStart = lib.concatStringsSep " " [
        "${pkgs.podman}/bin/podman run"
        "--cidfile=%t/%n.ctr-id"
        "--cgroups=no-conmon"
        "--rm"
        "--pod-id-file %t/pod-reverse_proxy.pod-id"
        "--sdnotify=conmon"
        "--replace"
        "--detach"

        # Auto-update label - enables podman-auto-update
        "--label io.containers.autoupdate=registry"

        "--name traefik"
        "--security-opt label=type:container_runtime_t"

        # Volume mounts
        "--volume %t/podman/podman.sock:/var/run/docker.sock:ro,Z"
        "--volume /data/traefik/acme.json:/acme.json:Z"

        # Traefik configuration via environment variables
        "--env TRAEFIK_LOG_LEVEL=DEBUG"
        "--env TRAEFIK_PROVIDERS_DOCKER=true"
        "--env TRAEFIK_PROVIDERS_DOCKER_EXPOSEDBYDEFAULT=false"
        "--env TRAEFIK_API_INSECURE=true"
        "--env TRAEFIK_API=true"
        "--env TRAEFIK_API_DASHBOARD=true"

        # Entry points
        "--env TRAEFIK_ENTRYPOINTS_WEB_ADDRESS=:80"
        "--env TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS=:443"
        "--env TRAEFIK_ENTRYPOINTS_LLDAPSECURE_ADDRESS=:636"

        # HTTP to HTTPS redirect
        "--env TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_TO=websecure"
        "--env TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_SCHEME=https"

        # Namecheap DNS challenge configuration
        "--env TRAEFIK_CERTIFICATESRESOLVERS_NAMECHEAP_ACME_DNSCHALLENGE=true"
        "--env TRAEFIK_CERTIFICATESRESOLVERS_NAMECHEAP_ACME_DNSCHALLENGE_PROVIDER=namecheap"
        "--env TRAEFIK_CERTIFICATESRESOLVERS_NAMECHEAP_ACME_DNSCHALLENGE_RESOLVERS=1.1.1.1:53"
        "--env TRAEFIK_CERTIFICATESRESOLVERS_NAMECHEAP_ACME_STORAGE=/acme.json"

        # Skip TLS verification for upstream servers
        "--env TRAEFIK_SERVERSTRANSPORT_INSECURESKIPVERIFY=true"

        # Traefik dashboard labels
        "--label traefik.enable=true"
        "--label traefik.http.routers.srv1.rule=Host(`srv1.nmsd.xyz`)"
        "--label traefik.http.routers.srv1.entrypoints=websecure"
        "--label traefik.http.routers.srv1.tls=true"
        "--label traefik.http.routers.srv1.tls.certresolver=namecheap"
        "--label traefik.http.services.cockpit-service.loadbalancer.server.url=https://host.docker.internal:9090"

        # Traefik API/Dashboard routing
        "--label traefik.http.routers.traefik.rule=Host(`traefik.nmsd.xyz`)"
        "--label traefik.http.routers.traefik.entrypoints=websecure"
        "--label traefik.http.routers.traefik.tls.certresolver=namecheap"
        "--label traefik.http.routers.traefik.middlewares=authelia"
        "--label traefik.http.routers.traefik.service=api@internal"

        # Container image
        "docker.io/library/traefik:latest"
      ];

      ExecStop = "${pkgs.podman}/bin/podman stop " + "--ignore -t 10 "
        + "--cidfile=%t/%n.ctr-id";

      ExecStopPost = "${pkgs.podman}/bin/podman rm " + "-f " + "--ignore -t 10 "
        + "--cidfile=%t/%n.ctr-id";
    };
  };

  # ============================================================================
  # Sops-nix Template: Traefik Secrets Environment File
  # ============================================================================
  # Creates an environment file with decrypted secrets for Traefik container
  # Format: KEY=value (systemd EnvironmentFile format)

  sops.templates."traefik-secrets" = {
    content = ''
      TRAEFIK_CERTIFICATESRESOLVERS_NAMECHEAP_ACME_EMAIL=${config.sops.placeholder.namecheap_email}
      NAMECHEAP_API_USER=${config.sops.placeholder.namecheap_api_user}
      NAMECHEAP_API_KEY=${config.sops.placeholder.namecheap_api_key}
    '';
    owner = "poddy";
    group = "poddy";
    mode = "0400";
  };
}
