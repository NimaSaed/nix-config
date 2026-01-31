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

  # Nutcracker-specific packages
  home.packages = with pkgs; [
    # Add nutcracker-specific tools here
    tmux
  ];

  # Nutcracker-specific program configurations
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
