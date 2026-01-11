{ config, lib, pkgs, ... }:

# Samba server configuration for sharing /data to nutcracker
# Security: SMB3 only, encryption required, signing mandatory
#
# SECRETS REQUIRED in secrets.yaml:
#   samba_password: "your-secure-password-here"
#
# The samba-user-setup service automatically configures the Samba user
# using the password from sops secrets - no manual smbpasswd needed.

let samba = config.services.samba.package;
in {
  # Decrypt the Samba password from sops
  sops.secrets.samba_password = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  # Enable Samba server
  services.samba = {
    enable = true;
    openFirewall = true;

    settings = {
      global = {
        # Server identification
        "workgroup" = "WORKGROUP";
        "server string" = "chestnut";
        "netbios name" = "chestnut";

        # ============================================================
        # SECURITY SETTINGS - Hardened for SMB3
        # ============================================================

        # Require authentication (no guest access)
        "security" = "user";
        "map to guest" = "never";

        # Enforce SMB3 minimum - blocks insecure SMB1/SMB2
        "server min protocol" = "SMB3";
        "client min protocol" = "SMB3";

        # Require encryption on all connections (SMB3 feature)
        "smb encrypt" = "required";

        # Require signing to prevent tampering and relay attacks
        "server signing" = "mandatory";
        "client signing" = "mandatory";

        # Network access control - restrict to private networks
        # Adjust these to match your specific network
        "hosts allow" =
          "192.168.0.0/16 10.0.0.0/8 172.16.0.0/12 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";

        # Disable insecure features
        "ntlm auth" = "ntlmv2-only";
        "lanman auth" = "no";
        "client lanman auth" = "no";
        "client ntlmv2 auth" = "yes";

        # ============================================================
        # PERFORMANCE TUNING
        # ============================================================
        "socket options" = "TCP_NODELAY IPTOS_LOWDELAY";
        "use sendfile" = "yes";
        "aio read size" = "16384";
        "aio write size" = "16384";

        # ============================================================
        # DISABLE UNUSED FEATURES
        # ============================================================
        "load printers" = "no";
        "printing" = "bsd";
        "printcap name" = "/dev/null";
        "disable spoolss" = "yes";

        # Logging
        "log level" = "1";
        "log file" = "/var/log/samba/smbd.log";
        "max log size" = "1000";
      };

      # Main data share
      "data" = {
        "path" = "/data";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";

        # Only allow poddy user to connect
        "valid users" = "poddy";

        # File creation masks - new files/dirs inherit parent permissions
        "create mask" = "0664";
        "directory mask" = "0775";
        "inherit permissions" = "yes";

        # VFS modules for extended attributes (useful for some apps)
        "vfs objects" = "streams_xattr";
      };
    };
  };

  # Enable Samba Web Services Discovery for network browsing (optional)
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  # Ensure Samba log directory exists
  systemd.tmpfiles.rules = [ "d /var/log/samba 0755 root root - -" ];

  # Automatically set up Samba user password from sops secret
  # This runs after samba-smbd starts and reads the password from sops
  # Reference: https://discourse.nixos.org/t/nixos-configuration-for-samba/17079
  systemd.services.samba-user-setup = {
    description = "Set up Samba user password for poddy";
    after = [ "samba-smbd.service" ];
    requires = [ "samba-smbd.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    # smbpasswd -s reads password from stdin (password repeated twice for confirmation)
    # smbpasswd -a adds user if not exists, updates password if exists
    script = ''
      PASSWORD=$(cat ${config.sops.secrets.samba_password.path} | tr -d '\n')
      (echo "$PASSWORD"; echo "$PASSWORD") | ${samba}/bin/smbpasswd -s -a poddy
    '';
  };
}
