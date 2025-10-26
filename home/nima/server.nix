{ config, pkgs, ... }:

{
  # Import shared core configurations
  imports = [
    ./common/core
  ];

  # Home Manager settings
  home = {
    username = "nima";
    homeDirectory = "/home/nima";
    stateVersion = "25.05";
  };

  # Server-specific packages
  home.packages = with pkgs; [
    # Add server-specific tools here
    tmux
    screen
  ];

  # Server-specific program configurations
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
