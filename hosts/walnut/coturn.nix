{ config, lib, ... }:
{
  services.coturn = {
    enable = true;
    no-cli = true; # disable management CLI (no local attack surface)
    use-auth-secret = true;
    static-auth-secret-file = # injected at runtime via replace-secret — never in Nix store
      config.sops.secrets."nextcloud/turn_secret".path;
    realm = "turn.nmsd.xyz";
    min-port = 49160; # narrow relay range, sufficient for home use
    max-port = 49200;
    extraConfig = ''
      total-quota=0
      bps-capacity=0
      stale-nonce
      no-multicast-peers
      denied-peer-ip=0.0.0.0-0.255.255.255
      denied-peer-ip=10.0.0.0-10.255.255.255
      denied-peer-ip=100.64.0.0-100.127.255.255
      denied-peer-ip=127.0.0.0-127.255.255.255
      denied-peer-ip=169.254.0.0-169.254.255.255
      denied-peer-ip=172.16.0.0-172.31.255.255
      denied-peer-ip=192.0.0.0-192.0.0.255
      denied-peer-ip=192.0.2.0-192.0.2.255
      denied-peer-ip=192.88.99.0-192.88.99.255
      denied-peer-ip=192.168.0.0-192.168.255.255
      denied-peer-ip=198.18.0.0-198.19.255.255
      denied-peer-ip=198.51.100.0-198.51.100.255
      denied-peer-ip=203.0.113.0-203.0.113.255
      denied-peer-ip=240.0.0.0-255.255.255.255
      denied-peer-ip=::1
      denied-peer-ip=64:ff9b::-64:ff9b::ffff:ffff
      denied-peer-ip=::ffff:0.0.0.0-::ffff:255.255.255.255
      denied-peer-ip=100::-100::ffff:ffff:ffff:ffff
      denied-peer-ip=2001::-2001:1ff:ffff:ffff:ffff:ffff:ffff:ffff
      denied-peer-ip=2002::-2002:ffff:ffff:ffff:ffff:ffff:ffff:ffff
      denied-peer-ip=fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
      denied-peer-ip=fe80::-febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff
    '';
  };

  networking.firewall = {
    allowedTCPPorts = [ 3478 ];
    allowedUDPPorts = [ 3478 ];
    allowedUDPPortRanges = [
      {
        from = 49160;
        to = 49200;
      }
    ];
  };

  sops.secrets."nextcloud/turn_secret" = {
    owner = "turnserver"; # user coturn runs as
  };
}
