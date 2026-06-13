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
    ./common/optional/sway.nix
    ./common/optional/bitwarden.nix
    ./common/optional/bitwarden-ssh-agent.nix
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
    # Input configuration for Goodix touchscreen
    input = {
      "type:touch" = {
        tap = "enabled";
      };
    };
  };

  home.packages = with pkgs; [
    firefox
    bitwarden-desktop
    playerctl
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
