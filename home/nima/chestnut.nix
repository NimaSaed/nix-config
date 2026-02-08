{ config, pkgs, ... }:

{
  # Import shared core configurations
  imports = [ ./common/core ];

  # Home Manager settings
  home = {
    username = "nima";
    homeDirectory = "/home/nima";
    stateVersion = "25.11";
  };

  # Chestnut-specific packages
  home.packages = with pkgs; [
    # Add chestnut-specific tools here
    tmux
  ];

  # Chestnut-specific program configurations
  programs = {
    # Enable home-manager
    home-manager.enable = true;

    # Tmux for terminal multiplexing
    tmux = {
      enable = true;
      terminal = "screen-256color";
      keyMode = "vi";
    };
  };
}
