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

  # Built-in input devices to switch off while a ZMK keyboard is plugged in
  # (see 61-zmk-inhibit-laptop-input.rules below): keyboard, TrackPoint,
  # touchpad (two nodes: the pad, and the TrackPoint buttons wired through
  # it) and the Fn-row hotkey devices. Power Button and Lid Switch are left
  # alone on purpose. Names as in /proc/bus/input/devices.
  laptopInputs = [
    "AT Translated Set 2 keyboard"
    "TPPS/2 Elan TrackPoint"
    "ELAN0676:00 04F3:3195 Touchpad"
    "ELAN0676:00 04F3:3195 Mouse"
    "ThinkPad Extra Buttons"
    "Intel HID events"
    "Video Bus"
    "Sleep Button"
  ];

  # Sets the kernel's per-device `inhibited` switch on laptopInputs: 1 if a ZMK
  # keyboard (USB 1d50:615e) is present, else 0. Stateless, so every trigger
  # just re-derives the right value. $1 is the devpath of a ZMK device being
  # removed, whose sysfs entry can outlive its remove uevent. Shell builtins
  # only, udev runs this with no PATH to speak of.
  zmkInhibitLaptopInput = pkgs.writeShellScript "zmk-inhibit-laptop-input" ''
    removed="''${1##*/}"
    inhibit=0
    for dev in /sys/bus/usb/devices/*; do
      [ "''${dev##*/}" = "$removed" ] && continue
      [ -r "$dev/idVendor" ] || continue
      read -r vendor < "$dev/idVendor" || continue
      read -r product < "$dev/idProduct" || continue
      if [ "$vendor:$product" = "1d50:615e" ]; then
        inhibit=1
        break
      fi
    done

    for dev in /sys/class/input/input*; do
      read -r name < "$dev/name" || continue
      case "$name" in
        ${lib.concatMapStringsSep " | " lib.escapeShellArg laptopInputs})
          echo "$inhibit" > "$dev/inhibited"
          ;;
      esac
    done
    exit 0
  '';
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

  # system-manager's userborn declares these groups itself; pin them to the
  # gids Ubuntu already assigned on this host so the existing groups are left
  # as they are.
  users.groups = {
    input.gid = 995;
    sgx.gid = 994;
    kvm.gid = 993;
    render.gid = 992;
  };

  # Device access for the ZSA keyboard (keymapp is installed via home-manager,
  # see home/nima/peanut.nix): hidraw for live training / Oryx pairing, DFU
  # bootloader for flashing. The uaccess tag makes logind grant an ACL to the
  # active seat session, so no extra group membership is needed. udevd picks up
  # rule changes on its own; replug the keyboard after switching.
  environment.etc."udev/rules.d/50-zsa-oryx.rules".source =
    "${pkgs.zsa-udev-rules}/lib/udev/rules.d/50-oryx.rules";
  environment.etc."udev/rules.d/50-zsa-wally.rules".source =
    "${pkgs.zsa-udev-rules}/lib/udev/rules.d/50-wally.rules";

  # Serial access for the ZMK keyboard (Halcyon Ferris). ZMK Studio
  # (https://zmk.studio, Web Serial in Firefox) opens the keyboard's USB
  # CDC-ACM port (/dev/ttyACM*) directly; Ubuntu ships those root:dialout
  # 0660, so the browser gets "access denied". Same uaccess approach as the
  # ZSA rules above, so no dialout membership. 1d50:615e is the shared ZMK
  # project USB ID, so this covers any ZMK board. Replug after switching.
  environment.etc."udev/rules.d/50-zmk-serial.rules".text = ''
    SUBSYSTEM=="tty", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="615e", TAG+="uaccess"
  '';

  # Ubuntu's hwdb tags every USB touchpad ID_INPUT_TOUCHPAD_INTEGRATION=internal
  # unless allow-listed, so libinput pairs the Voyager's touchpad with the lid
  # switch and disables it while the lid is closed (docked, clamshell). Tag it
  # external; libinput only lid-pairs internal touchpads. Runs after Ubuntu's
  # 70-touchpad.rules, which imports the hwdb value. Replug after switching.
  environment.etc."udev/rules.d/71-zsa-voyager-touchpad.rules".text = ''
    ACTION=="add|change", KERNEL=="event*", ENV{ID_INPUT_TOUCHPAD}=="1", ATTRS{idVendor}=="3297", ATTRS{idProduct}=="1977", ENV{ID_INPUT_TOUCHPAD_INTEGRATION}="external"
  '';

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

  # The Halcyon Ferris (ZMK; the wired RP2040 left half, or the dongle) is
  # not a boot-protocol keyboard (CONFIG_ZMK_USB_BOOT off), so usbhid does
  # not turn on its remote wakeup the way it does for the Voyager: the kernel
  # leaves it "disabled", never sends SET_FEATURE(REMOTE_WAKEUP) on suspend,
  # and a keypress cannot wake the laptop. Enable it here. Only effective once
  # the firmware advertises the capability (CONFIG_USB_DEVICE_REMOTE_WAKEUP=y
  # in nix-halcyon-ferris config/halcyon_wired.conf; the RP2040 Zephyr driver
  # does not imply it, unlike the nRF one) — until then power/wakeup reads
  # empty, the write fails with EINVAL and udev moves on. 1d50:615e is the
  # shared ZMK USB ID. Replug after switching.
  environment.etc."udev/rules.d/60-zmk-wakeup.rules".text = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="1d50", ATTR{idProduct}=="615e", ATTR{power/wakeup}="enabled"
  '';

  # With a ZMK keyboard plugged in, the split halves sit on top of the laptop's
  # own keyboard, so switch every built-in key and pointer off; unplugging
  # brings them back. Done with the kernel's `inhibited` switch rather than in
  # sway so it holds for every consumer (GDM, TTYs, swaylock, logind's sleep
  # key). The first two rules follow the ZMK device (ATTR is gone by the time
  # of the remove event, hence ENV{PRODUCT}); the third re-applies the state
  # when a built-in device (re)appears, which covers booting with the keyboard
  # attached and drivers re-creating a device after resume. USB only: a ZMK
  # board connected over Bluetooth does not trigger it. Replug after switching.
  environment.etc."udev/rules.d/61-zmk-inhibit-laptop-input.rules".text = ''
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="1d50", ATTR{idProduct}=="615e", RUN+="${zmkInhibitLaptopInput}"
    ACTION=="remove", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{PRODUCT}=="1d50/615e/*", RUN+="${zmkInhibitLaptopInput} %p"
    ACTION=="add", SUBSYSTEM=="input", KERNEL=="input*", ATTR{name}=="${lib.concatStringsSep "|" laptopInputs}", RUN+="${zmkInhibitLaptopInput}"
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
