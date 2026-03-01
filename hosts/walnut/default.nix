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

  networking.hostName = "walnut";

  # ============================================================================
  # Boot
  # ============================================================================

  boot.loader.grub.enable = true;

  # ============================================================================
  # WireGuard - Tunnel server (persistent public endpoint)
  # ============================================================================
  # walnut (10.99.0.1) is the server — chestnut (10.99.0.2) connects outbound to it.
  # chestnut lives behind NAT (UDM Pro), so walnut must be the stable endpoint.

  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.99.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = config.sops.secrets."wireguard/walnut_private_key".path;

    # MASQUERADE forwarded packets out through wg0 so chestnut sees 10.99.0.1 as source
    # and routes responses back through the tunnel to walnut (which then NATs back to client).
    postSetup = "${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE";
    postShutdown = "${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -o wg0 -j MASQUERADE";

    peers = [
      {
        # chestnut
        publicKey = "fjayqafC3ZyDGcp3LsM14CZCPjf/mJRpye+24p+S/ic=";
        allowedIPs = [ "10.99.0.2/32" ];
      }
    ];
  };

  # ============================================================================
  # NAT - Layer 4 port forwarding to chestnut via WireGuard
  # Traffic is forwarded as raw encrypted TCP — walnut never inspects TLS content.
  # ============================================================================

  networking.nat = {
    enable = true;
    externalInterface = "ens3";
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
  # 1. ssh root@<walnut-ip>
  # 2. ssh-keyscan <walnut-ip> | ssh-to-age  → get walnut age pubkey
  # 3. Add pubkey to .sops.yaml under &walnut
  # 4. Add creation_rule for hosts/walnut/secrets.yaml
  # 5. sops hosts/walnut/secrets.yaml  → add wireguard/walnut_private_key
  # 6. colmena apply --on walnut

  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.validateSopsFiles = true;
  sops.secrets."wireguard/walnut_private_key" = { };

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
