{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Work laptop (Lenovo P14s Gen 5) — standalone home-manager on top of Ubuntu.
  # Graphics for Nix apps are provided by nix-system-graphics (see hosts/peanut),
  # so sway and GUI apps run with hardware acceleration without nixGL wrapping.

  imports = [
    ./common/core
    ./common/optional/alacritty.nix
    ./common/optional/sway.nix
    ./common/optional/bitwarden.nix
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
  # Peanut-Specific Packages
  # ===========================================================================
  # Sway essentials and the bw-sops-key helper come from the imported modules.
  home.packages = with pkgs; [
    # Desktop applications (GL handled globally via /run/opengl-driver)
    firefox # Web browser
    slack # Team chat
    zoom-us # Video conferencing
    bitwarden-desktop # Password manager (GUI)

    # Fonts (matching the alacritty config / mac setup)
    nerd-fonts.open-dyslexic
    open-dyslexic
    nerd-fonts.jetbrains-mono
  ];

  # ===========================================================================
  # Fonts
  # ===========================================================================
  fonts.fontconfig.enable = true;

  # ===========================================================================
  # Program Configurations
  # ===========================================================================
  programs = {
    home-manager.enable = true;
  };
}
