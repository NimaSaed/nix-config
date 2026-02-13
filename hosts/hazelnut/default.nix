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
  # Networking
  # ============================================================================
  # Hazelnut - the coffee companion (LattePanda iota desktop)
  networking.hostName = "hazelnut";
  networking.networkmanager.enable = true;

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
  };

  # Fonts
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    nerd-fonts.jetbrains-mono
  ];

  # ============================================================================
  # Services
  # ============================================================================

  services.openssh = {
    enable = true;
  };

  # Periodic TRIM for eMMC longevity
  services.fstrim.enable = true;

  # ============================================================================
  # User Configuration
  # ============================================================================

  # Add dialout group for RP2040 co-processor serial access (/dev/ttyACM0)
  users.users.nima.extraGroups = [ "dialout" ];

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
