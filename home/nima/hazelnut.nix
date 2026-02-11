{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Import shared core configurations
  imports = [
    ./common/core
    ./common/optional/alacritty.nix
  ];

  # ===========================================================================
  # Home Manager Settings
  # ===========================================================================
  home = {
    username = "nima";
    homeDirectory = "/home/nima";
    stateVersion = "25.11";
  };

  # ===========================================================================
  # Hazelnut-Specific Packages
  # ===========================================================================
  home.packages = with pkgs; [
    # Sway utilities
    wl-clipboard # Wayland clipboard (wl-copy / wl-paste)
    grim # Screenshot tool
    slurp # Region selection for screenshots
    mako # Notification daemon
    fuzzel # Application launcher

    # Desktop tools
    pavucontrol # PulseAudio volume control (works with PipeWire)
    networkmanagerapplet # Network manager tray applet
  ];

  # ===========================================================================
  # Sway Window Manager
  # ===========================================================================
  wayland.windowManager.sway = {
    enable = true;
    config = {
      modifier = "Mod4"; # Super key
      terminal = "alacritty";
      menu = "fuzzel";

      # Input configuration for Goodix touchscreen
      input = {
        "type:touch" = {
          tap = "enabled";
        };
      };

      # Status bar
      bars = [
        {
          position = "top";
          statusCommand = "${pkgs.i3status}/bin/i3status";
        }
      ];

      # Basic keybindings (sway defaults + custom)
      keybindings = let
        mod = config.wayland.windowManager.sway.config.modifier;
      in lib.mkOptionDefault {
        "${mod}+Shift+s" = "exec ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy";
        "${mod}+l" = "exec swaylock -f -c 000000";
      };
    };
  };

  # ===========================================================================
  # Program Configurations
  # ===========================================================================
  programs = {
    home-manager.enable = true;

    # Tmux for terminal multiplexing
    tmux = {
      enable = true;
      terminal = "screen-256color";
      keyMode = "vi";
    };
  };
}
