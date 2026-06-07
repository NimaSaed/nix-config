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

  # Running home-manager on a non-NixOS distro (Ubuntu). Makes home-manager
  # export XDG_DATA_DIRS (including the Nix profile) into hm-session-vars.sh, so
  # launchers like fuzzel discover .desktop apps. The start-sway wrapper sources
  # that file, so the sway process — and apps launched from it — get it too.
  targets.genericLinux.enable = true;

  # ===========================================================================
  # Peanut-Specific Packages
  # ===========================================================================
  # Sway essentials and the bw-sops-key helper come from the imported modules.
  home.packages = with pkgs; [
    # Sway session launcher.
    # GDM execs the session command directly (not via a login shell), so the
    # home-manager environment (PATH, XDG_DATA_DIRS, session vars) isn't loaded
    # and apps launched from sway can't be found. This wrapper sources the
    # home-manager session vars first, then starts sway. Point the GDM
    # wayland-session entry at ~/.nix-profile/bin/start-sway (see hosts/peanut/README.md).
    (writeShellScriptBin "start-sway" ''
      if [ -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
        . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
      fi
      export PATH="$HOME/.nix-profile/bin:$PATH"
      exec sway "$@"
    '')

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
