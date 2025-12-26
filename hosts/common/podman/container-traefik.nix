{ config, lib, pkgs, ... }:

let
  # Capture the NixOS system config for use inside Home Manager
  # (where 'config' refers to HM config, not system config)
  nixosConfig = config;
in {
  # ============================================================================
  # Traefik Reverse Proxy - Rootless Podman Container via Quadlet
  # ============================================================================
  # This module uses Podman Quadlet (via quadlet-nix) to manage the Traefik
  # reverse proxy as a rootless container under the poddy user.
  #
  # HOW QUADLET WORKS:
  # - Instead of writing systemd units manually, we define .container/.pod/.network
  #   files in a declarative Nix syntax
  # - Podman's systemd generator converts these to proper systemd units at boot
  # - For rootless containers, files go to ~/.config/containers/systemd/
  # - The generator runs as part of the user's systemd startup, so permissions
  #   are handled correctly (solving our previous root ownership issues!)
  #
  # REQUIREMENTS:
  # - poddy user must exist with linger=true (import ../users/poddy)
  # - quadlet-nix modules imported in flake.nix
  # - sops-nix configured with Namecheap secrets
  # - /data/traefik/acme.json must exist with 600 permissions
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
  # Quadlet Configuration for poddy user
  # ============================================================================
  # All Quadlet configuration goes under home-manager.users.poddy.virtualisation.quadlet
  # This creates the appropriate .network, .pod, and .container files in
  # ~/.config/containers/systemd/ for the poddy user.

  home-manager.users.poddy = { pkgs, config, ... }: {
    # Enable Quadlet for this user
    virtualisation.quadlet = let
      # Reference the sops-nix template path from the NixOS SYSTEM config
      # Note: 'config' here is Home Manager config, so we use 'nixosConfig' captured above
      secretsPath = nixosConfig.sops.templates."traefik-secrets".path;
      # Get references to our defined networks and pods for cross-referencing
      # These come from the Home Manager quadlet config
      inherit (config.virtualisation.quadlet) networks pods;
    in {
      # ========================================================================
      # Network: reverse_proxy
      # ========================================================================
      # Creates a Podman network for containers to communicate.
      # Quadlet generates: reverse_proxy-network.service
      #
      # The .ref attribute provides a reference that other Quadlet units can use
      # to depend on this network (e.g., networks.reverse_proxy.ref)
      networks.reverse_proxy = {
        networkConfig = {
          # Network name as it appears in `podman network ls`
          networkName = "reverse_proxy";
        };
      };

      # ========================================================================
      # Pod: reverse_proxy
      # ========================================================================
      # Creates a Podman pod that groups related containers.
      # Containers in the same pod share:
      # - Network namespace (same IP, can communicate via localhost)
      # - Port mappings (defined at pod level)
      #
      # Quadlet generates: reverse_proxy-pod.service
      # Pod name comes from the attribute key (reverse_proxy)
      pods.reverse_proxy = {
        podConfig = {
          # Network to attach the pod to (singular 'network', not 'networks')
          # Uses the .ref from our network definition for proper dependency
          network = [ networks.reverse_proxy.ref ];

          # Port mappings: host_port:container_port
          # These are published on the pod, shared by all containers in it
          publishPorts = [
            "80:80"      # HTTP - Traefik web entrypoint
            "443:443"    # HTTPS - Traefik websecure entrypoint
            "8080:8080"  # Traefik Dashboard (internal access only)
            "636:636"    # LDAPS (future LDAP service)
          ];
        };
      };

      # ========================================================================
      # Container: traefik
      # ========================================================================
      # The Traefik reverse proxy container with:
      # - Namecheap DNS challenge for Let's Encrypt
      # - Automatic HTTPS redirects
      # - Dashboard on traefik1.nmsd.xyz
      #
      # Quadlet generates: traefik.service
      containers.traefik = {
        # Auto-start this container on boot (user login not required due to linger)
        autoStart = true;

        # Service configuration (passed to generated systemd unit)
        serviceConfig = {
          Restart = "always";
          TimeoutStartSec = 120;  # Allow time for image pull
        };

        # Unit configuration
        unitConfig = {
          Description = "Traefik reverse proxy container";
          # Depend on the pod being ready
          After = [ "reverse_proxy-pod.service" ];
        };

        containerConfig = {
          # Container image - using latest for auto-updates
          image = "docker.io/library/traefik:latest";

          # Join the reverse_proxy pod using .ref for proper dependency
          # This means ports are already mapped at pod level
          pod = pods.reverse_proxy.ref;

          # Auto-update label - enables `podman auto-update`
          labels = [
            "io.containers.autoupdate=registry"
            # Traefik configuration via labels
            "traefik.enable=true"
            # Dashboard routing
            "traefik.http.routers.traefik.rule=Host(`traefik1.nmsd.xyz`)"
            "traefik.http.routers.traefik.entrypoints=websecure"
            "traefik.http.routers.traefik.tls=true"
            "traefik.http.routers.traefik.tls.certresolver=namecheap"
            "traefik.http.routers.traefik.service=api@internal"
          ];

          # Volume mounts
          # %t = XDG_RUNTIME_DIR (e.g., /run/user/1001)
          # Note: NixOS doesn't use SELinux, so we omit :Z/:z options
          volumes = [
            # Podman socket for Docker provider (read-only)
            "%t/podman/podman.sock:/var/run/docker.sock:ro"
            # ACME certificates storage (rw needed for Let's Encrypt updates)
            "/data/traefik/acme.json:/acme.json"
          ];

          # Environment file with Namecheap secrets
          # This file is created by sops-nix
          environmentFiles = [ secretsPath ];

          # Traefik configuration via environment variables
          environments = {
            # Logging
            TRAEFIK_LOG_LEVEL = "DEBUG";

            # Docker provider configuration
            TRAEFIK_PROVIDERS_DOCKER = "true";
            TRAEFIK_PROVIDERS_DOCKER_EXPOSEDBYDEFAULT = "false";

            # API and Dashboard
            TRAEFIK_API = "true";
            TRAEFIK_API_DASHBOARD = "true";
            TRAEFIK_API_INSECURE = "true";

            # Entry points
            TRAEFIK_ENTRYPOINTS_WEB_ADDRESS = ":80";
            TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS = ":443";
            TRAEFIK_ENTRYPOINTS_LLDAPSECURE_ADDRESS = ":636";

            # HTTP to HTTPS redirect
            TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_TO = "websecure";
            TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_SCHEME = "https";

            # Namecheap DNS challenge configuration
            TRAEFIK_CERTIFICATESRESOLVERS_NAMECHEAP_ACME_DNSCHALLENGE = "true";
            TRAEFIK_CERTIFICATESRESOLVERS_NAMECHEAP_ACME_DNSCHALLENGE_PROVIDER = "namecheap";
            TRAEFIK_CERTIFICATESRESOLVERS_NAMECHEAP_ACME_DNSCHALLENGE_RESOLVERS = "1.1.1.1:53";
            TRAEFIK_CERTIFICATESRESOLVERS_NAMECHEAP_ACME_STORAGE = "/acme.json";

            # Skip TLS verification for upstream servers
            TRAEFIK_SERVERSTRANSPORT_INSECURESKIPVERIFY = "true";
          };

          # Security options
          securityLabelType = "container_runtime_t";
        };
      };
    };
  };

  # ============================================================================
  # Sops-nix Template: Traefik Secrets Environment File
  # ============================================================================
  # Creates an environment file with decrypted secrets for Traefik container
  # Format: KEY=value (systemd EnvironmentFile format)
  #
  # This is a system-level config because sops-nix operates at the system level.
  # The file is made readable by poddy user so the container can access it.

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
