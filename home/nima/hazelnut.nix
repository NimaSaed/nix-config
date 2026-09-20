{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Import shared core configurations
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

  # ===========================================================================
  # Hazelnut-Specific Sway Configuration
  # ===========================================================================
  # Common sway config + utilities come from ./common/optional/sway.nix.
  # Only host-specific bits live here.
  wayland.windowManager.sway.config = {
    input = {
      # Goodix touchscreen.
      "type:touch" = {
        tap = "enabled";
      };

      # The Voyager's touch navigator enumerates as a libinput touchpad with a
      # BUTTONPAD flag but no physical click, so with libinput defaults (tap
      # off, button_areas) there is no way to generate a button press at all.
      # Mirrors peanut's trackpad block: tap-to-click, two-finger tap for
      # right-click. drag_lock lets a tap-drag survive lifting the finger and
      # putting it back (within libinput's ~300 ms timeout), which the tiny
      # navigator surface needs for any selection wider than itself;
      # `enabled_sticky` would hold the drag until an explicit closing tap.
      "type:touchpad" = {
        tap = "enabled";
        drag_lock = "enabled";
        natural_scroll = "enabled";
        dwt = "enabled";
        click_method = "clickfinger";
      };
    };
  };

  # ===========================================================================
  # Idle display power-off (battery)
  # ===========================================================================
  # The LG 4K panel hangs off HDMI at 30 Hz. While the output is on, i915 has
  # an active pipe and never runtime-suspends, so the display engine and the
  # 3840x2160 scanout draw power around the clock. Ten minutes without input
  # powers the output off; i915 enters runtime suspend about 10 s later
  # (verified: power/runtime_status flips to `suspended`) and the monitor
  # drops to standby on its own. Any input turns it back on.
  #
  # Display-off only, no lock: the idle lock in the shared sway module was
  # disabled deliberately (badbc35). Fullscreen windows hold the timer off via
  # the shared `inhibit_idle` rules, so video playback is not interrupted.
  services.swayidle = {
    enable = true;
    timeouts = [
      {
        timeout = 600;
        command = "${pkgs.sway}/bin/swaymsg 'output * power off'";
        resumeCommand = "${pkgs.sway}/bin/swaymsg 'output * power on'";
      }
    ];
  };

  home.packages = with pkgs; [
    bitwarden-desktop
  ];

  # ===========================================================================
  # Program Configurations
  # ===========================================================================
  programs = {
    home-manager.enable = true;

    # Tmux for terminal multiplexing
    tmux = {
      enable = true;
      terminal = "screen-256color";
      keyMode = "vi";
    };
  };
}
