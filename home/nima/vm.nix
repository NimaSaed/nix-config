{ config, pkgs, ... }:

{
  # Import shared core configurations
  imports = [ ./common/core ];

  # Home Manager settings
  home = {
    username = "nima";
    homeDirectory = "/home/nima";
    stateVersion = "26.05";
  };

  # VM-specific packages
  home.packages = with pkgs; [
    # Add VM-specific tools here
  ];

  # VM-specific program configurations
  programs = {
    # Enable home-manager
    home-manager.enable = true;
  };
}
