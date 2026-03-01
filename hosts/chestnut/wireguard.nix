{ config, ... }:

{
  # ============================================================================
  # WireGuard - Client connecting outbound to walnut VPS
  # ============================================================================
  # chestnut initiates the tunnel outbound — no UDM Pro port forwarding needed.
  # persistentKeepalive keeps the NAT session alive so walnut can reach chestnut.

  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.99.0.2/24" ];
    privateKeyFile = config.sops.secrets."wireguard/chestnut_private_key".path;

    peers = [
      {
        publicKey = "qFDm8hM7t8hZMKSKu++CgFGBxHscIkSmcxcPF8P3y1s=";
        allowedIPs = [ "10.99.0.1/32" ];
        endpoint = "walnut.nmsd.xyz:51820";
        persistentKeepalive = 25; # essential: UDM Pro NAT tables expire without this
      }
    ];
  };

  sops.secrets."wireguard/chestnut_private_key" = {
    owner = "root";
  };
}
