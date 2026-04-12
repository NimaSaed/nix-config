{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.haos;
  domain = config.services.pods.domain;
  bridgeName = "br-haos";
in
{
  options.services.haos = {
    enable = lib.mkEnableOption "Home Assistant OS QEMU/KVM VM";

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "ha";
      description = "Traefik subdomain for HAOS (e.g. ha -> ha.domain)";
    };

    vmIp = lib.mkOption {
      type = lib.types.str;
      description = "Static LAN IP of the HAOS VM (set via UniFi DHCP reservation for macAddress)";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/haos";
      description = "Directory for HAOS disk image and OVMF vars";
    };

    bridge = lib.mkOption {
      type = lib.types.str;
      description = "Host physical NIC to bridge the VM onto (e.g. enp1s0)";
    };

    macAddress = lib.mkOption {
      type = lib.types.str;
      description = "Fixed MAC address for the VM NIC (52:54:00:xx:xx:xx range). Create a UniFi DHCP reservation for this MAC.";
    };

    haosVersion = lib.mkOption {
      type = lib.types.str;
      description = "Pinned HAOS release version (e.g. 14.2)";
    };

    haosHash = lib.mkOption {
      type = lib.types.str;
      description = "sha256 hash of haos_ova-<version>.qcow2.xz from GitHub releases";
    };

    memory = lib.mkOption {
      type = lib.types.int;
      default = 2048;
      description = "VM RAM in MB";
    };

    cpus = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Number of vCPUs";
    };

    diskSize = lib.mkOption {
      type = lib.types.str;
      default = "32G";
      description = "qemu-img resize target (no-op if image is already at or above this size)";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.elem "reverse-proxy" config.services.pods._enabledPods;
        message = "services.haos requires reverse-proxy (Traefik) to be enabled";
      }
    ];

    # ============================================================================
    # Bridge Networking
    # The VM gets a real LAN interface (required for mDNS/Thread discovery).
    # br-haos inherits the physical NIC's MAC so chestnut's existing DHCP lease
    # is unaffected. The VM uses a fixed MAC (cfg.macAddress) with its own
    # DHCP reservation.
    # ============================================================================
    networking.bridges."${bridgeName}".interfaces = [ cfg.bridge ];
    # Stop NetworkManager from fighting the enslaved physical NIC
    networking.networkmanager.unmanaged = [ "interface-name:${cfg.bridge}" ];
    # Bridge takes over the host's LAN IP via DHCP
    networking.interfaces."${bridgeName}".useDHCP = true;

    # Allow bridge networking in QEMU (required by qemu-bridge-helper)
    environment.etc."qemu/bridge.conf".text = ''
      allow ${bridgeName}
    '';

    # KVM acceleration — load both, kernel silently ignores the wrong CPU vendor
    boot.kernelModules = [
      "kvm-intel"
      "kvm-amd"
    ];

    # ============================================================================
    # Data Directory
    # ============================================================================
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 root root - -"
    ];

    # ============================================================================
    # HAOS Image Setup (oneshot — idempotent, skips if image already present)
    # ============================================================================
    systemd.services.haos-image-setup = {
      description = "Download and prepare HAOS disk image";
      wantedBy = [ "haos-vm.service" ];
      before = [ "haos-vm.service" ];
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "haos-image-setup" ''
          set -euo pipefail
          DEST="${cfg.dataDir}/haos.qcow2"
          VARS="${cfg.dataDir}/OVMF_VARS.fd"

          # Download image only if not already present
          if [ ! -f "$DEST" ]; then
            URL="https://github.com/home-assistant/operating-system/releases/download/${cfg.haosVersion}/haos_ova-${cfg.haosVersion}.qcow2.xz"
            TMP=$(mktemp -d)
            trap "rm -rf $TMP" EXIT
            echo "Downloading HAOS ${cfg.haosVersion}..."
            ${pkgs.curl}/bin/curl -L --fail -o "$TMP/haos.qcow2.xz" "$URL"
            ACTUAL=$(${pkgs.coreutils}/bin/sha256sum "$TMP/haos.qcow2.xz" | ${pkgs.coreutils}/bin/cut -d' ' -f1)
            EXPECTED="${cfg.haosHash}"
            if [ "$ACTUAL" != "$EXPECTED" ]; then
              echo "sha256 mismatch: got $ACTUAL, expected $EXPECTED" >&2
              exit 1
            fi
            echo "Decompressing..."
            ${pkgs.xz}/bin/xz -d -T0 "$TMP/haos.qcow2.xz"
            mv "$TMP/haos.qcow2" "$DEST"
            echo "Image ready: $DEST"
          fi

          # Grow disk if needed (no-op if already at or above target size)
          ${pkgs.qemu}/bin/qemu-img resize "$DEST" ${cfg.diskSize} || true

          # Copy writable OVMF vars (UEFI needs a per-VM writable vars store)
          if [ ! -f "$VARS" ]; then
            cp ${pkgs.OVMF.fd}/FV/OVMF_VARS.fd "$VARS"
            chmod 600 "$VARS"
          fi
        '';
      };
    };

    # ============================================================================
    # HAOS VM Service
    # ============================================================================
    systemd.services.haos-vm = {
      description = "Home Assistant OS QEMU/KVM VM";
      wantedBy = [ "multi-user.target" ];
      requires = [ "haos-image-setup.service" ];
      after = [
        "haos-image-setup.service"
        "network-online.target"
        "sys-subsystem-net-devices-${bridgeName}.device"
      ];

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "10s";

        ExecStart = lib.escapeShellArgs [
          "${pkgs.qemu}/bin/qemu-system-x86_64"
          "-name"
          "haos"
          "-machine"
          "q35,accel=kvm"
          "-cpu"
          "host"
          "-m"
          (toString cfg.memory)
          "-smp"
          (toString cfg.cpus)
          # HAOS disk
          "-drive"
          "file=${cfg.dataDir}/haos.qcow2,format=qcow2,if=virtio,cache=writeback"
          # Network — bridge with fixed MAC so UniFi DHCP reservation works
          "-netdev"
          "bridge,id=net0,br=${bridgeName}"
          "-device"
          "virtio-net-pci,netdev=net0,mac=${cfg.macAddress}"
          # UEFI firmware (HAOS x86_64 requires UEFI)
          "-drive"
          "if=pflash,format=raw,unit=0,file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd,readonly=on"
          "-drive"
          "if=pflash,format=raw,unit=1,file=${cfg.dataDir}/OVMF_VARS.fd"
          # No display — serial console for debugging via journalctl
          "-nographic"
          "-serial"
          "mon:stdio"
        ];
      };
    };

    # ============================================================================
    # Traefik Routing — label-carrier container
    # A minimal busybox container that exists solely to carry Traefik labels.
    # Traefik reads the labels and routes ha.<domain> → http://<vmIp>:8123.
    # Same pattern as the HA host-network container (loadbalancer.server.url).
    # ============================================================================
    home-manager.users.poddy =
      { pkgs, config, ... }:
      let
        inherit (config.virtualisation.quadlet) networks;
      in
      {
        virtualisation.quadlet.containers.haos-route = {
          autoStart = true;

          serviceConfig = {
            Restart = "always";
          };

          unitConfig = {
            Description = "Traefik label carrier for HAOS VM routing";
            After = [ "reverse_proxy-network.service" ];
          };

          containerConfig = {
            image = "docker.io/library/busybox:latest";
            exec = "sleep infinity";
            autoUpdate = "registry";
            networks = [ networks.reverse_proxy.ref ];

            labels = {
              "traefik.enable" = "true";
              "traefik.http.routers.homeassistant.rule" = "Host(`${cfg.subdomain}.${domain}`)";
              "traefik.http.routers.homeassistant.entrypoints" = "websecure";
              "traefik.http.routers.homeassistant.tls" = "true";
              "traefik.http.routers.homeassistant.tls.certresolver" = "letsencrypt";
              "traefik.http.routers.homeassistant.service" = "homeassistant";
              "traefik.http.services.homeassistant.loadbalancer.server.url" = "http://${cfg.vmIp}:8123";
            };
          };
        };
      };
  };
}
