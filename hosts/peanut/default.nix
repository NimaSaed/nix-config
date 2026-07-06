{ pkgs, ... }:

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
}
