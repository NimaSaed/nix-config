{ config, lib, pkgs, ... }:

# CIFS mount configuration for /data from chestnut
# Uses direct mount (not automount) so tmpfiles can create directories
#
# SECRETS REQUIRED in secrets.yaml:
#   smb_credentials: |
#     username=samby
#     password=your-secure-password-here
#
# The password must match the samba_password secret on chestnut
#
# References:
# - https://wiki.nixos.org/wiki/Samba
# - https://github.com/Mic92/sops-nix

let
  # Chestnut server address - use FQDN for reliable DNS resolution at boot
  sambaServer = "chestnut.nmsd.xyz";
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

  # CIFS mount - direct mount at boot (after network is up)
  # Using direct mount instead of automount so systemd-tmpfiles can create
  # directories under /data without being blocked by autofs detection
  fileSystems."${mountPoint}" = {
    device = "//${sambaServer}/${shareName}";
    fsType = "cifs";
    options = [
      # Network mount options
      "_netdev" # Mount after network is up
      "x-systemd.after=systemd-resolved.service" # Wait for DNS to be ready
      "x-systemd.device-timeout=30s"
      "x-systemd.mount-timeout=30s"
      # Note: NOT using "nofail" - boot should fail if mount fails
      # because podman services require /data to function

      # Security options for SMB3
      "vers=3.1.1" # SMB3.1.1 protocol (matches server)
      "seal" # Enable SMB3 encryption

      # Ownership mapping - files appear as poddy user locally
      "uid=${toString poddyUid}"
      "gid=${toString poddyGid}"
      "file_mode=0664"
      "dir_mode=0775"

      # Performance options
      "cache=strict"

      # Credentials
      "credentials=${config.sops.secrets.smb_credentials.path}"
    ];
  };

  # Ensure the mount point directory exists (before mount)
  systemd.tmpfiles.rules = [ "d ${mountPoint} 0755 root root - -" ];

  # Create directories under /data AFTER the CIFS mount is ready
  # systemd-tmpfiles-setup runs during sysinit.target (before network mounts)
  # so we need a separate service to create /data/* directories after mount
  systemd.services.data-dirs = {
    description = "Create directories on ${mountPoint} mount";
    after = [ "data.mount" ];
    requires = [ "data.mount" ];
    before = [ "home-manager-poddy.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.systemd}/bin/systemd-tmpfiles --create --prefix=${mountPoint}";
    };
  };
}
