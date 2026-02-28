{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  networking.hostName = "gateway";

  # ============================================================================
  # Boot
  # ============================================================================

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ============================================================================
  # WireGuard - Tunnel server (persistent public endpoint)
  # ============================================================================
  # gateway (10.99.0.1) is the server — chestnut (10.99.0.2) connects outbound to it.
  # chestnut lives behind NAT (UDM Pro), so gateway must be the stable endpoint.

  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.99.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = config.sops.secrets."gateway/wg_private_key".path;

    peers = [
      {
        # chestnut
        publicKey = "";
        allowedIPs = [ "10.99.0.2/32" ];
      }
    ];
  };

  # ============================================================================
  # NAT - Layer 4 port forwarding to chestnut via WireGuard
  # Traffic is forwarded as raw encrypted TCP — gateway never inspects TLS content.
  # ============================================================================

  networking.nat = {
    enable = true;
    externalInterface = "ens3";
    internalInterfaces = [ "wg0" ];
    forwardPorts = [
      {
        sourcePort = 80;
        proto = "tcp";
        destination = "10.99.0.2:80";
      }
      {
        sourcePort = 443;
        proto = "tcp";
        destination = "10.99.0.2:443";
      }
    ];
  };

  # ============================================================================
  # Firewall
  # ============================================================================

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22 # SSH
      80 # HTTP (forwarded to chestnut)
      443 # HTTPS (forwarded to chestnut)
    ];
    allowedUDPPorts = [
      51820 # WireGuard
    ];
  };

  # ============================================================================
  # Nix settings
  # ============================================================================

  nix.settings.experimental-features = "nix-command flakes";

  # ============================================================================
  # Secrets - sops-nix
  # ============================================================================
  # Bootstrap steps (one-time, after first boot):
  # 1. ssh root@<gateway-ip>
  # 2. ssh-keyscan <gateway-ip> | ssh-to-age  → get gateway age pubkey
  # 3. Add pubkey to .sops.yaml under &gateway
  # 4. Add creation_rule for hosts/gateway/secrets.yaml
  # 5. sops hosts/gateway/secrets.yaml  → add gateway/wg_private_key
  # 6. colmena apply --on gateway

  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.validateSopsFiles = false;
  sops.secrets."gateway/wg_private_key" = { };

  # ============================================================================
  # SSH
  # ============================================================================

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  users.users.root.openssh.authorizedKeys.keys = lib.splitString "\n" (
    builtins.readFile ../../home/nima/ssh.pub
  );

  # ============================================================================
  # Minimal system
  # ============================================================================

  environment.systemPackages = with pkgs; [
    wireguard-tools # for `wg show` debugging
  ];

  time.timeZone = "Europe/Amsterdam";

  system.stateVersion = "25.11";
}
