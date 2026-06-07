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

  # Lock command bound to <modifier>+l. Declared as an option so the keybinding
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
            "${mod}+l" = "exec ${config.my.sway.lockCommand}";
          };
      };
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
