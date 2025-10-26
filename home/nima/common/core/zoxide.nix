{ config, pkgs, ... }:

{
  programs.zoxide = {
    enable = true;

    # Enable bash integration
    enableBashIntegration = true;

    # Custom options
    options = [
      "--cmd cd" # Use 'cd' instead of 'z'
    ];
  };
}
