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

  # Running home-manager on a non-NixOS distro (Ubuntu). Makes home-manager
  # export XDG_DATA_DIRS (including the Nix profile) into hm-session-vars.sh, so
  # launchers like fuzzel discover .desktop apps. The start-sway wrapper sources
  # that file, so the sway process — and apps launched from it — get it too.
  targets.genericLinux.enable = true;

  # Use Ubuntu's swaylock for the lock screen. The Nix swaylock can't
  # authenticate via PAM on a non-NixOS distro (it loads PAM modules from
  # /nix/store, where there's no setuid helper to read /etc/shadow), so the
  # password is never accepted. The distro build is wired into the system PAM
  # stack. Install it with `sudo apt install swaylock` (see hosts/peanut/README.md).
  my.sway.lockCommand = "/usr/bin/swaylock -f -c 052B42"; # Nebius deep blue

  # Built-in panel: 14.5" 1920x1200 (310x200 mm) = 157 DPI — nearly the same
  # pixel density as the 27" 4K LG (163 DPI), so the DPI formula in
  # common/optional/sway.nix would give it the same scale, 1.75. But at 1.75
  # the laptop's logical space would be a cramped ~1097x686. Since a laptop
  # screen is viewed up close, smaller text is fine: pin 1.25 (logical
  # 1536x960). External monitors (home LG 4K, whatever the office dock has)
  # keep the automatic physical-size-based scale.
  my.sway.autoscale.overrides."eDP-1" = "1.25";

  # ThinkPad F12 "star" key — emits XF86Favorites. Toggle media play/pause.
  # playerctl talks MPRIS over D-Bus, so it controls whatever player is
  # active (Firefox, Spotify, mpv, …). `mkOptionDefault` is essential —
  # without it this definition would have higher priority than the shared
  # bindings (which use mkOptionDefault) and clobber every other keybinding,
  # including sway's built-in defaults.
  wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault {
    "XF86Favorites" = "exec ${lib.getExe pkgs.playerctl} play-pause";
  };

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
    unstable.zoom-us # Video conferencing
    bitwarden-desktop # Password manager (GUI)
    playerctl # MPRIS media control (play/pause on F12 / XF86Favorites)

    # Power management CLI. The boot-time `--auto-tune` runs as a root systemd
    # service in system-manager (hosts/peanut/default.nix), since auto-tune
    # writes /sys power knobs that home-manager's unprivileged user services
    # can't touch. This package is just for interactive use (`sudo powertop`).
    powertop

    # Dev tools
    github-cli
  ];

  # ===========================================================================
  # Program Configurations
  # ===========================================================================
  programs = {
    home-manager.enable = true;
  };
}
