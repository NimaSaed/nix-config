{ config, pkgs, ... }:

{
  programs.eza = {
    enable = true;

    # Enable bash integration for aliases
    enableBashIntegration = true;

    # Display git status
    git = true;

    # Show icons
    icons = "auto";

    # Extra options for eza
    extraOptions = [ "--group-directories-first" "--header" ];
  };
}
