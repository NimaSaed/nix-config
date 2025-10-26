{ config, pkgs, ... }:

{
  # Import shared core configurations
  imports = [
    ./common/core
  ];

  # Home Manager settings
  home = {
    username = "nima";
    homeDirectory = "/Users/nima";
    stateVersion = "25.05";
  };

  # macOS-specific packages
  home.packages = with pkgs; [
    # Add macOS-specific tools here
  ];

  # macOS-specific program configurations
  programs = {
    # Enable home-manager
    home-manager.enable = true;
  };

  # macOS-specific environment variables
  home.sessionVariables = {
    # Add any macOS-specific environment variables
  };
}
