{
  config,
  pkgs,
  lib,
  ...
}:

{
  # ===========================================================================
  # Sway Window Manager (shared, host-agnostic)
  # ===========================================================================
  # Common sway configuration reused across hosts. Host-specific bits (e.g.
  # touchscreen input, laptop idle/lid handling) live in the host file and
  # merge in via the module system.
  #
  # Package is left as the default `pkgs.sway`. On NixOS the graphics stack is
  # handled by the system; on a non-NixOS host (e.g. peanut) `/run/opengl-driver`
  # is populated by nix-system-graphics, so no nixGL wrapping is needed.

  # Lock command bound to <modifier>+Ctrl+l. Declared as an option so the keybinding
  # can be defined once here while each host overrides only the command when
  # needed — e.g. peanut points it at the system swaylock because the Nix
  # swaylock can't authenticate via PAM on a non-NixOS distro. Hosts that work
  # with the Nix swaylock (NixOS) need to set nothing.
  options.my.sway.lockCommand = lib.mkOption {
    type = lib.types.str;
    default = "${lib.getExe pkgs.swaylock} -f -c 000000";
    defaultText = lib.literalExpression ''"''${lib.getExe pkgs.swaylock} -f -c 000000"'';
    description = "Command bound to <modifier>+l to lock the screen.";
  };

  config = {
    wayland.windowManager.sway = {
      enable = true;
      config = {
        modifier = "Mod4"; # Super key
        # Absolute store paths so terminal/menu work even when sway is launched
        # from a display manager that doesn't put ~/.nix-profile/bin on PATH.
        terminal = lib.getExe pkgs.alacritty;
        menu = lib.getExe pkgs.fuzzel;

        # Focus workspace 1 on sway start (instead of whichever workspace the
        # first spawned window happens to land on).
        defaultWorkspace = "workspace number 1";

        # 10px gap around every window (between neighbours and between window
        # and screen edge).
        gaps.inner = 10;

        # Drop titlebars on both tiled and floating windows for a cleaner look.
        window.titlebar = false;
        floating.titlebar = false;

        # Assign applications to workspaces. Native-Wayland apps match on
        # `app_id`; XWayland apps match on `class`. For apps that may run
        # either way (Electron under different flag sets) we list both —
        # entries within a workspace's list are OR'd.
        assigns = {
          "1" = [ { app_id = "Alacritty"; } ];
          "2" = [
            { app_id = "firefox"; }
            { class = "Firefox"; }
          ];
          "3" = [
            { app_id = "Slack"; }
            { class = "Slack"; }
            { app_id = "Zoom"; }
            { class = "zoom"; }
          ];
        };

        # Bitwarden always floats, regardless of workspace.
        floating.criteria = [
          { app_id = "Bitwarden"; }
          { class = "Bitwarden"; }
        ];

        # Size Bitwarden to 50%×70% of the output and center it. `ppt` is
        # sway's percent-points unit; `move position center` runs after the
        # resize so the window is centered at its final size.
        window.commands = [
          {
            criteria.app_id = "Bitwarden";
            command = "resize set 50 ppt 70 ppt, move position center";
          }
          {
            criteria.class = "Bitwarden";
            command = "resize set 50 ppt 70 ppt, move position center";
          }
        ];

        # Status bar
        bars = [
          {
            position = "top";
            statusCommand = "${pkgs.i3status}/bin/i3status";
          }
        ];

        # Common keybindings. mkOptionDefault merges these with sway's built-in
        # defaults. The lock command is parameterised via my.sway.lockCommand.
        keybindings =
          let
            mod = config.wayland.windowManager.sway.config.modifier;
          in
          lib.mkOptionDefault {
            "${mod}+Shift+s" =
              "exec ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy";
            "${mod}+Ctrl+l" = "exec ${config.my.sway.lockCommand}";
            "${mod}+comma" = "move workspace to output left";
            "${mod}+period" = "move workspace to output right";
          };
      };
    };

    # =========================================================================
    # swayidle — lock before suspend
    # =========================================================================
    # Without an idle daemon listening on logind's PrepareForSleep signal,
    # closing the lid suspends straight to a logged-in session. swayidle holds
    # a systemd inhibit lock until the lock command returns, so the screen is
    # guaranteed locked before the kernel actually suspends.
    #
    # `-w` (wait mode) is critical: it makes swayidle wait for the lock
    # command to finish before releasing the inhibit. Up to home-manager
    # 24.11 the module added it automatically; from 24.11 onwards it has to
    # be passed via extraArgs. Drop this and suspend can race past the lock.
    services.swayidle = {
      enable = true;
      extraArgs = [ "-w" ];
      events = [
        {
          event = "before-sleep";
          command = config.my.sway.lockCommand;
        }
        {
          event = "lock";
          command = config.my.sway.lockCommand;
        }
      ];
    };

    # =========================================================================
    # Sway / Wayland utilities
    # =========================================================================
    home.packages = with pkgs; [
      wl-clipboard # Wayland clipboard (wl-copy / wl-paste)
      grim # Screenshot tool
      slurp # Region selection for screenshots
      mako # Notification daemon
      fuzzel # Application launcher
      swaylock # Screen locker
      i3status # Status bar content

      # Desktop tools
      pavucontrol # PulseAudio volume control (works with PipeWire)
      networkmanagerapplet # Network manager tray applet
    ];
  };
}
