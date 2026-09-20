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

  # PCIe ASPM: leave it to the BIOS. The board's FADT sets the NO_ASPM flag,
  # so the kernel ignores `pcie_aspm.policy=*` ("FADT indicates ASPM is
  # unsupported, using BIOS configuration"). Overriding that with
  # `pcie_aspm=force pcie_aspm.policy=powersave` was tried on 2026-09-20 and
  # only affected the BE200 link (r8169 disables L1 on its own, and the NIC
  # sits in D3 anyway). In two of four boots the BE200 dropped off the bus
  # within two minutes (all firmware registers 0xffffffff, iwlmld crash,
  # Wi-Fi gone until reboot). Not worth one link's L1.

  boot.kernel.sysctl = {
    # The perf-based hard-lockup detector arms an NMI timer on every core. It
    # only matters for debugging kernel hangs; drop the periodic wakeups.
    "kernel.nmi_watchdog" = 0;
    # Writeback flushes dirty pages every 5 s by default. 15 s batches the
    # writes so the eMMC controller stays runtime-suspended longer between
    # bursts. The UPS already covers mains loss, so the longer window costs
    # nothing in practice.
    "vm.dirty_writeback_centisecs" = 1500;
  };

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
  # Nothing is paired on this host, so keep the radio off until it is turned
  # on from blueman. A powered adapter runs page/inquiry scan windows on the
  # BE200's shared radio even with no peers; off, the USB function stays
  # runtime-suspended.
  hardware.bluetooth.powerOnBoot = false;
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
  boot.kernelModules = [
    "uinput"
    "hid-lattepanda-iota-ups"
  ];
  # The pack is 3 × Panasonic NCR18650GA, labelled 3300 mAh, 3.6 V nominal:
  # 35.64 Wh. The driver's default assumes 3 × 3500 mAh at 3.7 V. This only
  # scales the reported watts; UPower's time-to-empty is a ratio and unaffected.
  # The driver's charge_limit option must mirror DIP switch SW3. The switch is
  # in the full-charge position, matching the driver default of 100; set
  # charge_limit=80 here if it is ever moved to 80%CHG.
  boot.extraModprobeConfig = ''
    options hid-lattepanda-iota-ups energy_full_uwh=35640000
  '';

  # ============================================================================
  # Services
  # ============================================================================

  services.openssh = {
    enable = true;
  };

  services.udev.extraRules = ''
    KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
    KERNEL=="hidraw*", ATTRS{idVendor}=="2341", ATTRS{idProduct}=="8036", GROUP="input", MODE="0660"

    # Realtek RTL8168h NIC (02:00.0): the kernel leaves PCI runtime PM at
    # `on`, so the chip and its PHY sit in D0 with no cable plugged in. With
    # `auto`, r8169 suspends the device to D3hot whenever there is no carrier
    # (WoL is off, so the PHY powers down too) and its root port follows.
    # Plugging a cable in wakes it via the link-change interrupt.
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10ec", ATTR{device}=="0x8168", ATTR{power/control}="auto"

    # RP2040 co-processor (MicroPython, cdc_acm). USB devices default to
    # `on`; cdc_acm supports autosuspend and only allows it while the tty is
    # closed, so an open /dev/ttyACM0 session is never interrupted. The
    # Voyager keyboard and the UPS HID are left alone on purpose: usbhid
    # refuses autosuspend for interfaces with LEDs or without remote wakeup,
    # so a rule for them would be a no-op.
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2e8a", ATTR{idProduct}=="0005", ATTR{power/control}="auto"
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
