{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ../common/core
    ../common/users/nima
    ../common/optional/wifi.nix
  ];

  nixpkgs.config.permittedInsecurePackages = [ "electron-39.8.10" ];

  # ============================================================================
  # Boot Configuration
  # ============================================================================

  # Use systemd-boot (UEFI)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable zram swap for better memory management
  zramSwap.enable = true;
  zramSwap.memoryPercent = 50;

  # ============================================================================
  # Power Management — battery-backed (LattePanda IOTA UPS)
  # ============================================================================
  # CPU package power is capped to 5 W (PL1) in the BIOS; these trim the
  # platform's idle draw on top of that.

  # Let idle PCIe links (BE200 Wi-Fi, Realtek NIC) enter L0s/L1. The firmware
  # default leaves several links permanently in L0.
  boot.kernelParams = [ "pcie_aspm.policy=powersave" ];

  # HWP energy/performance hint: bias the hardware P-state algorithm toward
  # lower frequencies on bursty load and faster ramp-down after it. Peak and
  # PL1-limited sustained speed are unaffected. Firmware default is
  # balance_performance.
  systemd.tmpfiles.rules = [
    "w /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference - - - - balance_power"
  ];

  # ============================================================================
  # Networking
  # ============================================================================
  # Hazelnut - the coffee companion (LattePanda iota desktop)
  networking.hostName = "hazelnut";
  networking.networkmanager.enable = true;
  # 802.11 power save: the BE200 sleeps between AP beacons instead of listening
  # continuously. Costs tens of ms of inbound latency after idle; saves a
  # noticeable share of this board's idle draw on battery.
  networking.networkmanager.wifi.powersave = true;

  # ============================================================================
  # Localization
  # ============================================================================

  time.timeZone = "Europe/Amsterdam";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "nl_NL.UTF-8";
    LC_IDENTIFICATION = "nl_NL.UTF-8";
    LC_MEASUREMENT = "nl_NL.UTF-8";
    LC_MONETARY = "nl_NL.UTF-8";
    LC_NAME = "nl_NL.UTF-8";
    LC_NUMERIC = "nl_NL.UTF-8";
    LC_PAPER = "nl_NL.UTF-8";
    LC_TELEPHONE = "nl_NL.UTF-8";
    LC_TIME = "nl_NL.UTF-8";
  };

  # ============================================================================
  # Graphics — Intel Alder Lake-N (i915)
  # ============================================================================
  hardware.graphics.enable = true;

  # ============================================================================
  # Audio — PipeWire (Intel HDA PCH + Realtek codec + HDMI outputs)
  # ============================================================================
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;

  # ============================================================================
  # Bluetooth — Intel BE200
  # ============================================================================
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  # ============================================================================
  # Desktop — Sway (Wayland compositor)
  # ============================================================================
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  # Login manager — greetd with tuigreet
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd sway";
        user = "greeter";
      };
    };
  };

  # XDG Desktop Portal for Sway (screen sharing, file dialogs)
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    # Route the Settings interface (color-scheme) to the gtk backend; without a
    # backend serving it under sway, GTK4/libadwaita and Electron apps can't
    # read light/dark and default to light. Screencast/screenshot stay on wlr.
    config.sway = {
      default = [ "gtk" ];
      "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
      "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
    };
  };

  # Fonts
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    nerd-fonts.jetbrains-mono
  ];

  # ============================================================================
  # LattePanda IOTA UPS (DFR1247) — battery percentage via HID
  # ============================================================================
  # The UPS presents as Arduino Leonardo (0x2341:0x8036). This out-of-tree
  # driver exposes it as a power_supply device so upower and i3status-rust
  # pick it up automatically. Upstream patch v3 by Andrew Maney, pending merge:
  # https://lkml.iu.edu/hypermail/linux/kernel/2605.2/12097.html
  boot.extraModulePackages = [
    (config.boot.kernelPackages.callPackage ./hid-lattepanda-iota-ups { })
  ];
  boot.kernelModules = [ "uinput" "hid-lattepanda-iota-ups" ];

  # ============================================================================
  # Services
  # ============================================================================

  services.openssh = {
    enable = true;
  };

  services.udev.extraRules = ''
    KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
    KERNEL=="hidraw*", ATTRS{idVendor}=="2341", ATTRS{idProduct}=="8036", GROUP="input", MODE="0660"
  '';

  # UPower — computes time-to-empty/full from capacity change rate so that
  # i3status-rust can display remaining time (the UPS hardware only reports %).
  services.upower.enable = true;

  # Periodic TRIM for eMMC longevity
  services.fstrim.enable = true;

  # ============================================================================
  # User Configuration
  # ============================================================================

  # dialout: RP2040 co-processor serial access (/dev/ttyACM0)
  # input: xremap reads keyboards and writes /dev/uinput for virtual events.
  users.users.nima.extraGroups = [
    "dialout"
    "input"
  ];

  # Configure root user for emergency mode access
  users.users.root = {
    initialHashedPassword = "$y$j9T$VIgEJ4u79wZRwEny9XepM1$1sYHPUO7bIl5PQtSYE.Ptra8zIFBQyh1AlxKmfAkFg/";
    openssh.authorizedKeys.keys = lib.splitString "\n" (builtins.readFile ../../home/nima/ssh.pub);
  };

  # ============================================================================
  # Secrets Management — sops-nix
  # ============================================================================
  sops = {
    defaultSopsFile = ./secrets.yaml;
    validateSopsFiles = false;
    age.keyFile = "/var/lib/sops-nix/key.txt";
  };

  system.stateVersion = "25.11";
}
