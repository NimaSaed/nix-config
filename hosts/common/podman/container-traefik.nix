{ config, lib, pkgs, ... }:

{
  # ============================================================================
  # Traefik Reverse Proxy - Rootless Podman Container
  # ============================================================================
  # This module creates systemd system services (running as poddy user) for the
  # Traefik reverse proxy running in a rootless Podman pod. The configuration
  # mirrors the systemd units from pod-reverse_proxy.service and container-traefik.service.
  #
  # REQUIREMENTS:
  # - poddy user must exist (import ../users/poddy)
  # - sops-nix configured with Namecheap secrets
  # - /data/traefik/acme.json must exist with 600 permissions
  # - Firewall ports 80 and 443 opened (configured automatically by this module)
  #
  # SECRETS (via sops-nix):
  # - namecheap_email
  # - namecheap_api_user
  # - namecheap_api_key

  # ============================================================================
  # Firewall Configuration
  # ============================================================================
  # Open required ports for Traefik reverse proxy
  # Port 80: HTTP (web entrypoint) - redirects to HTTPS
  # Port 443: HTTPS (websecure entrypoint) - main traffic

  networking.firewall = {
    allowedTCPPorts = [
      80    # HTTP - Traefik web entrypoint (auto-redirects to HTTPS)
      443   # HTTPS - Traefik websecure entrypoint
      # 8080  # Traefik API/Dashboard (keep closed for security)
      # 636   # LDAPS (for future LDAP service)
    ];
  };

  # ============================================================================
  # Network Service: reverse_proxy
  # ============================================================================
  # Creates the Podman network before the pod starts
  # This prevents "network not found" errors on first deployment

  systemd.services.create-reverse_proxy-network = {
    description = "Create reverse_proxy Podman network";
    wantedBy = [ "multi-user.target" ];
    before = [ "pod-reverse_proxy.service" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "poddy";
      Group = "poddy";
      # Explicitly set Podman config paths and PATH for rootless tools
      Environment = [
        "XDG_CONFIG_HOME=/data/poddy/config"
        "XDG_DATA_HOME=/data/poddy/containers"
        "XDG_RUNTIME_DIR=/run/user/1001"
        "PATH=/run/wrappers/bin:${lib.makeBinPath [ pkgs.shadow pkgs.coreutils pkgs.podman pkgs.fuse-overlayfs ]}"
      ];
      # Ensure runtime containers directory exists
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /run/user/1001/containers";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.podman}/bin/podman network exists reverse_proxy || ${pkgs.podman}/bin/podman network create reverse_proxy'";
    };
  };

  # ============================================================================
  # Pod Service: reverse_proxy
  # ============================================================================
  # Creates a Podman pod with published ports for HTTP/HTTPS/Dashboard/LDAPS

  systemd.services.pod-reverse_proxy = {
    description = "Podman pod-reverse_proxy";
    documentation = [ "man:podman-generate-systemd(1)" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "create-reverse_proxy-network.service" ];
    wantedBy = [ "multi-user.target" ];

    unitConfig = {
      RequiresMountsFor = "/run/user/1001/containers";
    };

    serviceConfig = {
      User = "poddy";
      Group = "poddy";
      # Explicitly set Podman config paths and PATH for rootless tools
      Environment = [
        "PODMAN_SYSTEMD_UNIT=%n"
        "XDG_CONFIG_HOME=/data/poddy/config"
        "XDG_DATA_HOME=/data/poddy/containers"
        "XDG_RUNTIME_DIR=/run/user/1001"
        "PATH=/run/wrappers/bin:${lib.makeBinPath [ pkgs.shadow pkgs.coreutils pkgs.podman pkgs.fuse-overlayfs ]}"
      ];
      Restart = "always";
      TimeoutStopSec = 70;
      Type = "forking";
      PIDFile = "/run/user/1001/pod-reverse_proxy.pid";

      ExecStartPre = [
        # Ensure runtime containers directory exists
        "${pkgs.coreutils}/bin/mkdir -p /run/user/1001/containers"
        ("${pkgs.podman}/bin/podman pod create "
        + "--infra-conmon-pidfile /run/user/1001/pod-reverse_proxy.pid "
        + "--pod-id-file /run/user/1001/pod-reverse_proxy.pod-id " + "--exit-policy=stop "
        + "--name reverse_proxy " + "--network reverse_proxy "
        + "--publish 80:80/tcp " + "--publish 443:443/tcp "
        + "--publish 8080:8080/tcp " + "--publish 636:636/tcp " + "--replace")
      ];

      ExecStart = "${pkgs.podman}/bin/podman pod start "
        + "--pod-id-file /run/user/1001/pod-reverse_proxy.pod-id";

      ExecStop = "${pkgs.podman}/bin/podman pod stop " + "--ignore "
        + "--pod-id-file /run/user/1001/pod-reverse_proxy.pod-id " + "-t 10";

      ExecStopPost = "${pkgs.podman}/bin/podman pod rm " + "--ignore " + "-f "
        + "--pod-id-file /run/user/1001/pod-reverse_proxy.pod-id";
    };
  };

  # ============================================================================
  # Container Service: traefik
  # ============================================================================
  # Traefik reverse proxy container with:
  # - Namecheap DNS challenge for Let's Encrypt
  # - Automatic HTTPS redirects
  # - Dashboard on traefik1.nmsd.xyz (no authentication)

  systemd.services.container-traefik = {
    description = "Podman container-traefik";
    documentation = [ "man:podman-generate-systemd(1)" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "pod-reverse_proxy.service" ];
    bindsTo = [ "pod-reverse_proxy.service" ];
    wantedBy = [ "multi-user.target" ];

    unitConfig = {
      RequiresMountsFor = "/run/user/1001/containers";
    };

    serviceConfig = {
      User = "poddy";
      Group = "poddy";
      # Explicitly set Podman config paths and PATH for rootless tools
      Environment = [
        "PODMAN_SYSTEMD_UNIT=%n"
        "XDG_CONFIG_HOME=/data/poddy/config"
        "XDG_DATA_HOME=/data/poddy/containers"
        "XDG_RUNTIME_DIR=/run/user/1001"
        "PATH=/run/wrappers/bin:${lib.makeBinPath [ pkgs.shadow pkgs.coreutils pkgs.podman pkgs.fuse-overlayfs ]}"
      ];
      Restart = "always";
      TimeoutStopSec = 70;
      Type = "notify";
      NotifyAccess = "all";

      # Load secrets as environment variables
      # These files are created by sops-nix at /run/user/1001/secrets/
      EnvironmentFile = [ "${config.sops.templates."traefik-secrets".path}" ];

      # Ensure runtime containers directory exists
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /run/user/1001/containers";

      ExecStart = lib.concatStringsSep " " [
        "${pkgs.podman}/bin/podman run"
        "--cidfile=/run/user/1001/%n.ctr-id"
        "--cgroups=no-conmon"
        "--rm"
        "--pod-id-file /run/user/1001/pod-reverse_proxy.pod-id"
        "--sdnotify=conmon"
        "--replace"
        "--detach"

        # Auto-update label - enables podman-auto-update
        "--label io.containers.autoupdate=registry"

        "--name traefik"
        "--security-opt label=type:container_runtime_t"

        # Volume mounts
        "--volume /run/user/1001/podman/podman.sock:/var/run/docker.sock:ro,Z"
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

        # Traefik API/Dashboard routing
        "--label traefik.http.routers.traefik.rule=Host(`traefik1.nmsd.xyz`)"
        "--label traefik.http.routers.traefik.entrypoints=websecure"
        "--label traefik.http.routers.traefik.tls=true"
        "--label traefik.http.routers.traefik.tls.certresolver=namecheap"
        "--label traefik.http.routers.traefik.service=api@internal"

        # Container image
        "docker.io/library/traefik:latest"
      ];

      ExecStop = "${pkgs.podman}/bin/podman stop " + "--ignore -t 10 "
        + "--cidfile=/run/user/1001/%n.ctr-id";

      ExecStopPost = "${pkgs.podman}/bin/podman rm " + "-f " + "--ignore -t 10 "
        + "--cidfile=/run/user/1001/%n.ctr-id";
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
