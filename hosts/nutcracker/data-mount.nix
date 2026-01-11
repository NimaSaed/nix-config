{ config, lib, pkgs, ... }:

# CIFS mount configuration for /data from chestnut
# Uses systemd automount for reliability and sops-nix for credentials
#
# SECRETS REQUIRED in secrets.yaml:
#   smb_credentials: |
#     username=poddy
#     password=your-secure-password-here
#
# The password must match what you set with `smbpasswd -a poddy` on chestnut
#
# References:
# - https://wiki.nixos.org/wiki/Samba
# - https://github.com/Mic92/sops-nix

let
  # Chestnut server address - use IP or hostname (must be resolvable)
  sambaServer = "chestnut";
  shareName = "data";
  mountPoint = "/data";

  # User/group IDs for mounted files (poddy runs containers)
  poddyUid = 1001;
  poddyGid = 1001;
in {
  # Required for mount.cifs
  environment.systemPackages = [ pkgs.cifs-utils ];

  # Decrypt SMB credentials from sops
  # File will be available at /run/secrets/smb_credentials
  sops.secrets.smb_credentials = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  # CIFS mount with systemd automount
  # Mount is triggered on first access, preventing boot hangs if server unavailable
  fileSystems."${mountPoint}" = {
    device = "//${sambaServer}/${shareName}";
    fsType = "cifs";
    options = let
      # Automount options - prevents hanging on network issues
      # Source: https://wiki.nixos.org/wiki/Samba
      automount_opts = lib.concatStringsSep "," [
        "x-systemd.automount"
        "noauto"
        "x-systemd.idle-timeout=60"
        "x-systemd.device-timeout=5s"
        "x-systemd.mount-timeout=5s"
      ];

      # Security options for SMB3
      security_opts = lib.concatStringsSep "," [
        "vers=3.1.1" # SMB3.1.1 protocol (matches server)
        "seal" # Enable SMB3 encryption
      ];

      # Ownership mapping - files appear as poddy user locally
      ownership_opts = lib.concatStringsSep "," [
        "uid=${toString poddyUid}"
        "gid=${toString poddyGid}"
        "file_mode=0664"
        "dir_mode=0775"
      ];

      # Performance and reliability options
      perf_opts = lib.concatStringsSep "," [
        "cache=strict"
        "_netdev" # Network filesystem - mount after network is up
      ];

    in [
      automount_opts
      security_opts
      ownership_opts
      perf_opts
      "credentials=${config.sops.secrets.smb_credentials.path}"
    ];
  };

  # Ensure the mount point directory exists
  systemd.tmpfiles.rules = [ "d ${mountPoint} 0755 root root - -" ];
}
