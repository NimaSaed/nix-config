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
    ./common/optional/claude-code.nix
    ./common/optional/sway.nix
    ./common/optional/gtk.nix
    ./common/optional/bitwarden.nix
    ./common/optional/bitwarden-ssh-agent.nix
    ./common/optional/firefox.nix
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

  # System-wide colour theme (terminal, sway, notifications). See
  # home/nima/common/core/theme.nix for the palette set.
  my.activeTheme = "nebius";

  # Route the desktop portal's Settings interface to the gtk backend under sway.
  # Without this, XDG_CURRENT_DESKTOP=sway leaves no backend serving
  # org.freedesktop.portal.Settings, so GTK4/libadwaita (Nautilus) and
  # Electron/Chromium (Slack, Bitwarden) can't read color-scheme and fall back
  # to light. Screencast/screenshot stay on wlr (the sway-native backend).
  # On NixOS this is done via xdg.portal.config (see hosts/hazelnut); Ubuntu
  # has no such layer, so we drop the per-user config file directly.
  xdg.configFile."xdg-desktop-portal/sway-portals.conf".text = ''
    [preferred]
    default=gtk
    org.freedesktop.impl.portal.ScreenCast=wlr
    org.freedesktop.impl.portal.Screenshot=wlr
  '';

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

  # Clamshell mode: disable the built-in panel when the lid closes so windows
  # move to the external monitor (which becomes primary); re-enable on open.
  # --locked keeps it working over the lock screen; --reload re-applies the
  # state on config reload. eDP-1 is the laptop panel (see autoscale override
  # above). logind leaves the machine awake when docked and still suspends on
  # lid close when no external monitor is connected.
  wayland.windowManager.sway.extraConfig = ''
    bindswitch --reload --locked lid:on output eDP-1 disable
    bindswitch --reload --locked lid:off output eDP-1 enable
  '';

  # Touchpad behaviour for the built-in trackpad. Without this sway falls back
  # to libinput defaults (no tap-to-click, traditional scroll direction), which
  # feel wrong on a laptop. `dwt` (disable-while-typing) suppresses stray cursor
  # jumps from the palm while typing; `clickfinger` makes a two-finger press the
  # right-click instead of carving out a bottom-right button zone. Lives here
  # rather than the shared module because it's per-device — desktops have no
  # touchpad, and hazelnut configures its touchscreen the same host-local way.
  wayland.windowManager.sway.config.input."type:touchpad" = {
    tap = "enabled";
    natural_scroll = "enabled";
    dwt = "enabled";
    click_method = "clickfinger";
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
