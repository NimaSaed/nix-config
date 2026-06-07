{
  config,
  pkgs,
  lib,
  ...
}:

{
  # ===========================================================================
  # Sway Window Manager (shared, host-agnostic)
  # ===========================================================================
  # Common sway configuration reused across hosts. Host-specific bits (e.g.
  # touchscreen input, laptop idle/lid handling) live in the host file and
  # merge in via the module system.
  #
  # Package is left as the default `pkgs.sway`. On NixOS the graphics stack is
  # handled by the system; on a non-NixOS host (e.g. peanut) `/run/opengl-driver`
  # is populated by nix-system-graphics, so no nixGL wrapping is needed.

  wayland.windowManager.sway = {
    enable = true;
    config = {
      modifier = "Mod4"; # Super key
      terminal = "alacritty";
      menu = "fuzzel";

      # Status bar
      bars = [
        {
          position = "top";
          statusCommand = "${pkgs.i3status}/bin/i3status";
        }
      ];

      # Common keybindings (sway defaults + custom)
      keybindings =
        let
          mod = config.wayland.windowManager.sway.config.modifier;
        in
        lib.mkOptionDefault {
          "${mod}+Shift+s" =
            "exec ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy";
          "${mod}+l" = "exec swaylock -f -c 000000";
        };
    };
  };

  # ===========================================================================
  # Sway / Wayland utilities
  # ===========================================================================
  home.packages = with pkgs; [
    wl-clipboard # Wayland clipboard (wl-copy / wl-paste)
    grim # Screenshot tool
    slurp # Region selection for screenshots
    mako # Notification daemon
    fuzzel # Application launcher
    swaylock # Screen locker
    i3status # Status bar content

    # Desktop tools
    pavucontrol # PulseAudio volume control (works with PipeWire)
    networkmanagerapplet # Network manager tray applet
  ];
}
