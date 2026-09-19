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
    ./common/core/fonts.nix
    ./common/optional/alacritty.nix
    ./common/optional/claude-code.nix
    ./common/optional/sway.nix
    ./common/optional/gtk.nix
    ./common/optional/bitwarden.nix
    ./common/optional/bitwarden-ssh-agent.nix
    ./common/optional/firefox.nix
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
  # Hazelnut-Specific Sway Configuration
  # ===========================================================================
  # Common sway config + utilities come from ./common/optional/sway.nix.
  # Only host-specific bits live here.
  wayland.windowManager.sway.config = {
    input = {
      # Goodix touchscreen.
      "type:touch" = {
        tap = "enabled";
      };

      # The Voyager's touch navigator enumerates as a libinput touchpad with a
      # BUTTONPAD flag but no physical click, so with libinput defaults (tap
      # off, button_areas) there is no way to generate a button press at all.
      # Mirrors peanut's trackpad block: tap-to-click, two-finger tap for
      # right-click. drag_lock lets a tap-drag survive lifting the finger and
      # putting it back (within libinput's ~300 ms timeout), which the tiny
      # navigator surface needs for any selection wider than itself;
      # `enabled_sticky` would hold the drag until an explicit closing tap.
      "type:touchpad" = {
        tap = "enabled";
        drag_lock = "enabled";
        natural_scroll = "enabled";
        dwt = "enabled";
        click_method = "clickfinger";
      };
    };
  };

  home.packages = with pkgs; [
    bitwarden-desktop
  ];

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
