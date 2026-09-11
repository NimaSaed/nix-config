{ lib, pkgs, ... }:

let
  # Kernel command-line additions. Ubuntu owns /etc/default/grub, so these go in
  # as a drop-in under /etc/default/grub.d and reach the boot loader once
  # grub.cfg is regenerated (grub-kernel-params below).
  kernelParams = [
    # i915 drives the panel backlight through an interface it doesn't support
    # from kernel 7.0.0-28 on, so brightness keys silently do nothing.
    # TODO: drop this once a fixed kernel ships.
    # https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2161359
    "i915.enable_dpcd_backlight=0"
  ];
in
{
  # system-manager module for peanut (Lenovo P14s Gen 5, work laptop).
  #
  # Ubuntu 24.04 owns the base OS; this manages a thin slice of system state via
  # system-manager:
  #   - nix-system-graphics populates /run/opengl-driver so Nix-built GL/Vulkan
  #     apps (sway, firefox, ...) use the Intel GPU instead of software rendering.
  #   - a sysctl drop-in re-enables the unprivileged user-namespace sandbox so
  #     Chromium/Electron apps (Slack, Bitwarden) can sandbox themselves.
  #
  # Apply (root, rarely — only on driver/config changes):
  #   sudo nix run github:numtide/system-manager -- switch --flake '.#peanut'
  #
  # See ./README.md for full laptop setup steps.

  nixpkgs.hostPlatform = "x86_64-linux";

  # Allow running system-manager on a non-NixOS distro (Ubuntu).
  system-manager.allowAnyDistro = true;

  # xremap needs read access to /dev/input/event* and write access to /dev/uinput
  # for its virtual keyboard. Ubuntu already has the input group (gid 995 on
  # this host); keep membership additive so system-manager does not replace the
  # existing Ubuntu-managed account/group set.
  users.groups = {
    input.gid = 995;
    sgx.gid = 994;
    kvm.gid = 993;
    render.gid = 992;
  };
  systemd.services.xremap-input-access = {
    description = "Grant xremap input/uinput access";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udevd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "xremap-input-access" ''
        ${pkgs.kmod}/bin/modprobe uinput
        ${pkgs.shadow}/bin/usermod -a -G input nima
        ${pkgs.systemd}/bin/udevadm control --reload
        ${pkgs.systemd}/bin/udevadm trigger --subsystem-match=input || true
        chgrp input /dev/uinput
        chmod 0660 /dev/uinput
      '';
    };
  };

  environment.etc."udev/rules.d/70-xremap-uinput.rules".text = ''
    KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
  '';

  # Device access for the ZSA keyboard (keymapp is installed via home-manager,
  # see home/nima/peanut.nix): hidraw for live training / Oryx pairing, DFU
  # bootloader for flashing. The uaccess tag makes logind grant an ACL to the
  # active seat session, so no extra group membership is needed. udevd picks up
  # rule changes on its own; replug the keyboard after switching.
  environment.etc."udev/rules.d/50-zsa-oryx.rules".source =
    "${pkgs.zsa-udev-rules}/lib/udev/rules.d/50-oryx.rules";
  environment.etc."udev/rules.d/50-zsa-wally.rules".source =
    "${pkgs.zsa-udev-rules}/lib/udev/rules.d/50-wally.rules";

  # The Voyager hangs off the CalDigit TS4's two USB 2.0 hubs. Its own remote
  # wakeup is on (usbhid enables it for boot-protocol keyboards), but the kernel
  # leaves hubs' wakeup off, and many hubs will not relay a downstream wake
  # request upstream unless their own remote wakeup is enabled, so a keypress
  # could not wake the laptop from suspend. Trade-off: connect/disconnect
  # events at the dock wake it too. Applies to hubs enumerated after the rule
  # is in place: replug the dock, or `udevadm trigger` the hubs after switching.
  environment.etc."udev/rules.d/60-caldigit-ts4-wakeup.rules".text = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2188", ATTR{idProduct}=="5802", ATTR{power/wakeup}="enabled"
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2188", ATTR{idProduct}=="5510", ATTR{power/wakeup}="enabled"
  '';

  # Provide system-wide graphics drivers for Nix apps (Intel Mesa by default).
  system-graphics.enable = true;

  # Ubuntu 24.04 restricts unprivileged user namespaces via AppArmor, which
  # breaks the Chromium/Electron sandbox for Nix-store apps (their chrome-sandbox
  # can't be setuid in the read-only store). Re-enable it so Slack/Bitwarden run
  # sandboxed instead of aborting.
  environment.etc."sysctl.d/60-apparmor-userns.conf".text = ''
    kernel.apparmor_restrict_unprivileged_userns = 0
  '';

  # PAM stack for swaylock — defers to Ubuntu's common-* stack so the lock
  # screen authenticates exactly like sudo and gdm-password. Once
  # `pam_fprintd.so` is in common-auth (enabled via `sudo pam-auth-update`
  # alongside GNOME's fingerprint setup), swaylock prompts for fingerprint
  # first and falls back to password. The Ubuntu swaylock apt package ships
  # its own minimal PAM file; system-manager replaces it with this one.
  environment.etc."pam.d/swaylock".text = ''
    auth    include    common-auth
    account include    common-account
    session include    common-session
  '';

  # PowerTOP auto-tuning. Applies powertop's recommended power-saving settings
  # (PCIe ASPM, USB autosuspend, SATA link power management, etc.) on every
  # boot. These write to /sys and need root, so this is a system service rather
  # than a home-manager user service. oneshot + RemainAfterExit: it runs once,
  # the kernel keeps the settings, and the unit shows active afterward.
  systemd.services.powertop = {
    description = "PowerTOP auto-tuning for power saving";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.powertop}/bin/powertop --auto-tune";
      # auto-tune flips every power knob it finds, two of which break audio:
      #   - snd_hda_intel power_save=1 suspends the SOF/HDA codec after 1s
      #     idle; the wake-up latency stalls PipeWire's graph clock (clicking,
      #     video frozen frame-by-frame) whenever output switches or resumes.
      #   - USB autosuspend on audio-class devices (the USB-C monitor's hub
      #     carries a mic) makes them vanish mid-stream with I/O errors.
      # Re-assert audio-safe values right after. Only boot-time devices need
      # the USB pass: devices hot-plugged later default to power/control=on,
      # powertop only touches what is present when it runs. Shell builtins
      # (read/echo) only — no coreutils on PATH in system-manager services.
      ExecStartPost = pkgs.writeShellScript "powertop-audio-exceptions" ''
        echo 0 > /sys/module/snd_hda_intel/parameters/power_save
        echo N > /sys/module/snd_hda_intel/parameters/power_save_controller
        for iface in /sys/bus/usb/devices/*/bInterfaceClass; do
          [ -f "$iface" ] || continue
          read -r class < "$iface"
          [ "$class" = "01" ] || continue
          echo on > "''${iface%/*}/../power/control"
        done
      '';
    };
  };

  # systemd-sysctl only reads the drop-in at boot; apply it on activation too.
  systemd.services.apparmor-userns-sysctl = {
    description = "Re-enable unprivileged user namespaces (Electron sandbox)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-sysctl.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.procps}/bin/sysctl -w kernel.apparmor_restrict_unprivileged_userns=0";
    };
  };

  environment.etc."default/grub.d/99-nix-kernel-params.cfg".text = ''
    GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT ${lib.concatStringsSep " " kernelParams}"
  '';

  # The drop-in above only reaches the boot loader once grub.cfg is regenerated,
  # which Ubuntu does on kernel upgrades but not on system-manager activation.
  systemd.services.grub-kernel-params = {
    description = "Regenerate grub.cfg for the Nix-managed kernel parameters";
    wantedBy = [ "multi-user.target" ];
    unitConfig.RequiresMountsFor = "/boot/grub";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # update-grub is a wrapper that execs grub-mkconfig by bare name, and the
      # /etc/grub.d scripts it runs expect Ubuntu's tools, so hand it Ubuntu's
      # PATH — system-manager's unit PATH is Nix-only.
      ExecStart = pkgs.writeShellScript "grub-kernel-params" ''
        for param in ${lib.escapeShellArgs kernelParams}; do
          ${pkgs.gnugrep}/bin/grep -qF -- "$param" /boot/grub/grub.cfg && continue
          export PATH=/usr/sbin:/usr/bin:/sbin:/bin
          exec /usr/sbin/update-grub
        done
      '';
    };
  };

  # Home DNS. At home the router's DHCP hands out public resolvers, and the work
  # tailnet's MagicDNS claims the catch-all routing domain (~.), so
  # systemd-resolved never asks the home resolver and chestnut.nmsd.xyz does not
  # resolve (Colmena fails at the SSH step). Pin the home resolver on the home
  # Wi-Fi profile and route only nmsd.xyz to it: a specific routing domain beats
  # ~., so everything else, work names included, still goes through Tailscale.
  # Per profile rather than a resolved.conf drop-in so it only applies at home;
  # elsewhere nmsd.xyz must resolve publicly (via walnut). The profile stays
  # Ubuntu-managed (it holds the Wi-Fi PSK), hence nmcli instead of a keyfile;
  # use Ubuntu's nmcli to match its NetworkManager. Applies on next (re)connect.
  systemd.services.home-wifi-dns =
    let
      homeWifiProfiles = [ "88-Work" ];
      homeDns = "10.10.10.1";
      homeDomain = "nmsd.xyz";
    in
    {
      description = "Pin the home DNS resolver on home Wi-Fi profiles";
      wantedBy = [ "multi-user.target" ];
      after = [ "NetworkManager.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "home-wifi-dns" ''
          for profile in ${lib.escapeShellArgs homeWifiProfiles}; do
            /usr/bin/nmcli connection show "$profile" >/dev/null 2>&1 || continue
            /usr/bin/nmcli connection modify "$profile" \
              ipv4.dns ${homeDns} \
              ipv4.ignore-auto-dns yes \
              ipv4.dns-search "~${homeDomain}"
          done
        '';
      };
    };
}
