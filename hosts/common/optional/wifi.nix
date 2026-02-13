{ config, ... }:

{
  # WiFi secrets from sops
  # Each host must provide wifi/ssid and wifi/password in its secrets.yaml
  sops.secrets."wifi/ssid" = {};
  sops.secrets."wifi/password" = {};

  sops.templates."wifi-env" = {
    content = ''
      WIFI_SSID=${config.sops.placeholder."wifi/ssid"}
      WIFI_PSK=${config.sops.placeholder."wifi/password"}
    '';
  };

  # WiFi auto-connect via NetworkManager
  # Requires: networking.networkmanager.enable = true (set per-host)
  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.sops.templates."wifi-env".path ];
    profiles.home-wifi = {
      connection = {
        id = "home-wifi";
        type = "wifi";
        autoconnect = true;
      };
      wifi = {
        ssid = "$WIFI_SSID";
        mode = "infrastructure";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "$WIFI_PSK";
      };
      ipv4 = {
        method = "auto";
      };
      ipv6 = {
        method = "auto";
        addr-gen-mode = "stable-privacy";
      };
    };
  };
}
