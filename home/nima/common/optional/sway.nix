{
  config,
  pkgs,
  lib,
  ...
}:

let
  # UI colours come from the active system theme's semantic map (my.ui, derived
  # from my.activeTheme — see home/nima/common/core/theme.nix).
  ui = config.my.ui;
  # fuzzel expects colours as RRGGBBAA hex with no leading '#'.
  fz = c: "${lib.toLower (lib.removePrefix "#" c)}ff";
  kanataConfig = ./oryx-layout.kbd;
  xremapConfig = "${config.xdg.configHome}/xremap/config.yml";
in
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

  # Lock command bound to <modifier>+Backspace. Declared as an option so the keybinding
  # can be defined once here while each host overrides only the command when
  # needed — e.g. peanut points it at the system swaylock because the Nix
  # swaylock can't authenticate via PAM on a non-NixOS distro. Hosts that work
  # with the Nix swaylock (NixOS) need to set nothing.
  options.my.sway.lockCommand = lib.mkOption {
    type = lib.types.str;
    default = "${lib.getExe pkgs.swaylock} -f -c ${lib.removePrefix "#" ui.surface}";
    defaultText = lib.literalExpression ''"''${lib.getExe pkgs.swaylock} -f -c 052B42"'';
    description = "Command bound to <modifier>+Backspace to lock the screen.";
  };

  # Automatic per-output scaling from the panel's physical dimensions (EDID).
  # Docks and office monitors vary, so instead of hardcoding scales per output
  # name we compute DPI = pixels / physical-width and pick the scale that gets
  # text to a comfortable size, rounded to quarter steps (1.0, 1.25, 1.5, …).
  # Outputs whose size or scale shouldn't follow the formula (e.g. the built-in
  # laptop panel, where a personal preference wins) go in `overrides`.
  options.my.sway.autoscale = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically set output scale based on physical DPI.";
    };
    targetDpi = lib.mkOption {
      type = lib.types.int;
      # Effective (post-scale) DPI to aim for. 96 is the classic desktop DPI;
      # with it a 27" 4K LG (163 DPI) lands on scale 1.75, a 27" 1440p office
      # monitor (~109 DPI) on 1.25, and a 24" 1080p (~92 DPI) on 1.0.
      default = 96;
      description = "Target effective DPI; scale = panel DPI / targetDpi, rounded to 0.25.";
    };
    overrides = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "eDP-1" = "1.75";
      };
      description = "Fixed scale per output name, bypassing the DPI formula.";
    };
  };

  config = {
    wayland.windowManager.sway = {
      enable = true;
      config = {
        modifier = "Mod4"; # Super key
        # Absolute store paths so terminal/menu work even when sway is launched
        # from a display manager that doesn't put ~/.nix-profile/bin on PATH.
        terminal = lib.getExe pkgs.alacritty;
        # mkDefault so a host can swap the launcher command (peanut wraps it to
        # list only Nix-installed apps — see home/nima/peanut.nix).
        menu = lib.mkDefault (lib.getExe pkgs.fuzzel);

        # Focus workspace 1 on sway start (instead of whichever workspace the
        # first spawned window happens to land on).
        defaultWorkspace = "workspace number 1";

        # 10px gap around every window (between neighbours and between window
        # and screen edge).
        gaps.inner = 10;

        # Drop titlebars on both tiled and floating windows for a cleaner look.
        window.titlebar = false;
        floating.titlebar = false;

        # Solid themed desktop background on every output.
        output."*".bg = "${ui.desktop} solid_color";

        # Window decoration colors. Titlebars are off, so in practice these
        # paint borders and the split indicator: the accent marks the focused
        # window, unfocused borders match the background so only gaps separate
        # them, and the urgent colour flags urgency.
        colors = {
          focused = {
            border = ui.accent;
            background = ui.surface;
            text = ui.onSurface;
            indicator = ui.indicator;
            childBorder = ui.accent;
          };
          focusedInactive = {
            border = ui.surface;
            background = ui.surface;
            text = ui.muted;
            indicator = ui.surface;
            childBorder = ui.surface;
          };
          unfocused = {
            border = ui.surface;
            background = ui.surface;
            text = ui.muted;
            indicator = ui.surface;
            childBorder = ui.surface;
          };
          urgent = {
            border = ui.urgent;
            background = ui.urgent;
            text = ui.onUrgent;
            indicator = ui.urgent;
            childBorder = ui.urgent;
          };
        };

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
          ];
          "4" = [
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
            command = "resize set 90 ppt 70 ppt, move position center";
          }
          {
            criteria.class = "Bitwarden";
            command = "resize set 90 ppt 70 ppt, move position center";
          }
          # Hold off the idle timeouts (below) whenever a window is fullscreen —
          # fullscreen video and Zoom screen-share/calls shouldn't blank or lock
          # the screen mid-stream. Browsers already inhibit idle via the Wayland
          # idle-inhibit protocol when playing video; these rules cover apps that
          # don't (e.g. Zoom) by keying off fullscreen state. `.*` matches every
          # window — app_id for native Wayland, class for XWayland.
          {
            criteria.app_id = ".*";
            command = "inhibit_idle fullscreen";
          }
          {
            criteria.class = ".*";
            command = "inhibit_idle fullscreen";
          }
        ];

        # Mic and speaker start muted but pre-set to sensible levels, so the
        # first unmute lands at 70%/50% rather than wherever they were left.
        startup = [
          { command = "${pkgs.pamixer}/bin/pamixer --set-volume 50 --mute"; }
          { command = "${pkgs.pamixer}/bin/pamixer --default-source --set-volume 70 --mute"; }
        ];

        # Status bar — themed bar with the focused workspace highlighted in the
        # accent colour (text auto-contrasted via onAccent for readability).
        # Status line content comes from i3status-rust (configured below).
        bars = [
          {
            position = "top";
            statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ${config.xdg.configHome}/i3status-rust/config-top.toml";
            # Breathing room around tray icons (Slack, Bitwarden, nm-applet);
            # the sway default of 2px leaves them nearly touching the screen
            # edge. Padding applies per icon, so it also spaces them apart.
            trayPadding = 10;
            colors = {
              background = ui.surface;
              statusline = ui.onSurface;
              separator = ui.muted;
              focusedWorkspace = {
                border = ui.accent;
                background = ui.accent;
                text = ui.onAccent;
              };
              activeWorkspace = {
                border = ui.surface;
                background = ui.surface;
                text = ui.accent;
              };
              inactiveWorkspace = {
                border = ui.surface;
                background = ui.surface;
                text = ui.muted;
              };
              urgentWorkspace = {
                border = ui.urgent;
                background = ui.urgent;
                text = ui.onUrgent;
              };
            };
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

            # Backspace is a thumb tap, opposite the left home-row Super key.
            "${mod}+BackSpace" = "exec ${config.my.sway.lockCommand}";
            # Both directions chained: autoscale stacks laptop+external
            # vertically (up/down applies), wdisplays can arrange side-by-side
            # (left/right applies). In a two-output layout only the direction
            # that exists takes effect, so the keys work in either arrangement.
            "${mod}+comma" = "move workspace to output left; move workspace to output up";
            "${mod}+period" = "move workspace to output right; move workspace to output down";

            # Laptop media-key row. XF86 keysyms only fire on keyboards that
            # have them, so these are harmless on desktops with plain keyboards.
            # pamixer talks to the system PipeWire via the pulse-compat socket;
            # brightnessctl uses logind so no setuid/udev rules needed.
            "XF86AudioMute" = "exec ${pkgs.pamixer}/bin/pamixer -t";
            "XF86AudioLowerVolume" = "exec ${pkgs.pamixer}/bin/pamixer -d 5";
            "XF86AudioRaiseVolume" = "exec ${pkgs.pamixer}/bin/pamixer -i 5";
            "XF86AudioMicMute" = "exec ${pkgs.pamixer}/bin/pamixer --default-source -t";
            # Media play/pause via MPRIS (browsers, Spotify, mpv, …). Bound to
            # the XF86AudioPlay keysym my ZSA keyboard emits, used across hosts.
            "XF86AudioPlay" = "exec ${lib.getExe pkgs.playerctl} play-pause";
            "XF86MonBrightnessDown" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set 5%-";
            "XF86MonBrightnessUp" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set +5%";
            # Full-screen screenshot to clipboard. F9 (PrtSc) emits Print.
            "Print" = "exec ${pkgs.grim}/bin/grim - | ${pkgs.wl-clipboard}/bin/wl-copy";
            # ThinkPad F10 emits XF86Launch2 — alias to region-select (same as
            # Mod+Shift+s) so the hardware key matches the chord shortcut.
            "XF86Launch2" =
              "exec ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy";
            # ThinkPad F7 (monitor icon) — pop up a GUI display picker for
            # layout / mirror / extend. Hand-rolled wlr-randr scripts break when
            # ports change, so we lean on wdisplays.
            "XF86Display" = "exec ${lib.getExe pkgs.wdisplays}";
          };
      };

      extraConfig = ''
        seat * hide_cursor 1500
        seat * hide_cursor when-typing enable

        mode "Power: (s) shutdown  (r) reboot  (l) logout" {
            bindsym s exec systemctl poweroff
            bindsym r exec systemctl reboot
            bindsym l exec ${pkgs.sway}/bin/swaymsg exit
            bindsym Return mode default
            bindsym Escape mode default
        }
        bindsym --no-warn Mod4+Shift+e mode "Power: (s) shutdown  (r) reboot  (l) logout"
      '';
    };

    # =========================================================================
    # i3status-rust — status line content
    # =========================================================================
    # Block set carried over from the pre-nix i3blocks bar (NimaSaed/dotfiles):
    # wifi signal + bandwidth, memory, disk, temperature, cpu, battery,
    # Tehran/Kuala-Lumpur clocks plus a local week clock, and speaker + mic
    # volume. Unlike the old shell blocklets, sound and net blocks are
    # event-driven (PipeWire / netlink), so no pkill -RTMIN refresh hacks.
    #
    # The blocks themselves color by state (good/warning/critical), themed from
    # the active palette: accent for good, urgent for warning, inverted urgent
    # for critical.
    programs.i3status-rust = {
      enable = true;
      bars.top = {
        # Material Design icons; glyphs come from the Nerd Font symbols
        # package in home.packages via fontconfig fallback.
        icons = "material-nf";
        settings.theme = {
          theme = "plain";
          overrides = {
            idle_bg = ui.surface;
            idle_fg = ui.onSurface;
            info_bg = ui.surface;
            info_fg = ui.muted;
            good_bg = ui.surface;
            good_fg = ui.accent;
            warning_bg = ui.surface;
            warning_fg = ui.urgent;
            critical_bg = ui.urgent;
            critical_fg = ui.onUrgent;
            separator_bg = ui.surface;
            separator_fg = ui.muted;
          };
        };
        blocks = [
          {
            # Wifi quality + ssid when wireless, plus live up/down rates.
            # Hidden entirely when there is no default route, matching the
            # old wifi blocklet's behavior on wired desktops.
            block = "net";
            format = " $icon {$signal_strength $ssid |}^icon_net_down $speed_down.eng(prefix:K) ^icon_net_up $speed_up.eng(prefix:K) ";
            missing_format = "";
          }
          {
            block = "memory";
            format = " $icon $mem_avail.eng(prefix:Gi) ";
            interval = 60;
          }
          {
            # Free space on the filesystem holding $HOME; the default
            # thresholds turn it red below 10% free like the old blocklet.
            block = "disk_space";
            path = config.home.homeDirectory;
            interval = 300;
          }
          {
            block = "temperature";
            format = " $icon $max ";
            interval = 60;
            warning = 70;
          }
          {
            block = "cpu";
            interval = 1;
          }
          {
            block = "battery";
            format = " $icon $percentage {$time |}";
          }
          # Secondary timezones (old bar's IR/MY clocks), then the local
          # clock with ISO week number.
          {
            block = "time";
            format = " IR$timestamp.datetime(f:'%H%M') ";
            timezone = "Asia/Tehran";
          }
          {
            block = "time";
            format = " MY$timestamp.datetime(f:'%H%M') ";
            timezone = "Asia/Kuala_Lumpur";
          }
          {
            block = "time";
            format = " $icon Week: $timestamp.datetime(f:'%V %A %d %B %H:%M') ";
          }
          # Speaker, then microphone. Left-click toggles mute, scroll
          # adjusts volume; both update instantly on PipeWire events.
          { block = "sound"; }
          {
            block = "sound";
            device_kind = "source";
          }
        ];
      };
    };

    # =========================================================================
    # fuzzel — application launcher (theme-driven)
    # =========================================================================
    # The sway menu (bound to Mod+d). Colours follow the active theme via my.ui:
    # accent border, accent-filled selection with auto-contrasted text, and the
    # accent used to highlight the matched substring.
    programs.fuzzel = {
      enable = true;
      settings = {
        main = {
          # fuzzel resolves .desktop Icon= names against its own icon-theme (not
          # the GTK one), defaulting to the sparse hicolor — so apps that ship no
          # icon (Slack, Zoom) show blank. Point it at Papirus (same theme the
          # rest of the desktop uses), which has matching app icons.
          icon-theme = "Papirus";
          # Command used to launch Terminal=true apps (nvim, htop, btop, …).
          # Alacritty with a distinct app_id so they open in the focused
          # workspace rather than being pinned to workspace 1 by the assign rule;
          # fuzzel appends the program after this. (yazi has its own entry above.)
          terminal = "${lib.getExe pkgs.alacritty} --class fuzzel-term -e";
        };
        border = {
          width = 2;
          radius = 10;
        };
        colors = {
          background = fz ui.surface;
          text = fz ui.onSurface;
          match = fz ui.accent;
          selection = fz ui.accent;
          selection-text = fz ui.onAccent;
          selection-match = fz ui.onAccent;
          border = fz ui.accent;
        };
      };
    };

    # =========================================================================
    # yazi — terminal file manager (launched from fuzzel)
    # =========================================================================
    # yazi is a TUI, so it runs inside a terminal. Launching it in a normal
    # Alacritty window would inherit app_id "Alacritty" and get pinned to
    # workspace 1 by the assign rule above. The desktop entry instead starts
    # Alacritty with a distinct app_id ("yazi"), so fuzzel opens it in whatever
    # workspace is focused. Vim keybindings (hjkl, gg/G, /, …) are yazi's default.
    programs.yazi.enable = true;
    xdg.desktopEntries.yazi = {
      name = "Yazi";
      comment = "Terminal file manager";
      exec = "${lib.getExe pkgs.alacritty} --class yazi -e ${lib.getExe pkgs.yazi}";
      terminal = false;
      icon = "system-file-manager";
      categories = [
        "Utility"
        "System"
      ];
    };

    # Kanata implements the Voyager layout in software for ordinary keyboards.
    # It grabs every keyboard except the ZSA Voyager, exposes one virtual
    # `kanata-oryx` device, and blocks every physical key outside the 33-key
    # layout except volume controls. ThinkPad media/Fn events normally come
    # from separate partial-key devices, which Kanata deliberately leaves alone.
    systemd.user.services.kanata-oryx = {
      Unit = {
        Description = "Oryx layout for non-ZSA keyboards";
        PartOf = [ "sway-session.target" ];
        After = [ "sway-session.target" ];
      };
      Service = {
        ExecStart = "${lib.getExe pkgs.kanata} --cfg ${kanataConfig}";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "sway-session.target" ];
    };

    # xremap remains the application-aware second stage. It reads Kanata's
    # virtual keyboard plus the firmware-managed Voyager, so Firefox-specific
    # mappings work with either without racing Kanata to grab physical devices.
    # Firefox uses Ctrl+T/Ctrl+W for new/close tab. Remap the easier home-row Alt
    # variants only inside Firefox; native Alt+number tab selection and
    # Alt+Left/Right history navigation need no translation.
    #
    # `exact_match: true` leaves Alt+Shift variants and every other application
    # untouched.
    xdg.configFile."xremap/config.yml".text = ''
      keymap:
        - name: Firefox Alt tab controls
          application:
            only: [firefox, Firefox]
          exact_match: true
          remap:
            Alt-t: Ctrl-t
            Alt-w: Ctrl-w
    '';

    systemd.user.services.xremap = {
      Unit = {
        Description = "App-aware keyboard remapping";
        PartOf = [ "sway-session.target" ];
        Wants = [ "kanata-oryx.service" ];
        After = [
          "sway-session.target"
          "kanata-oryx.service"
        ];
      };
      Service = {
        # --output-device-name is pinned: without it xremap renames itself to
        # "xremap pid=NN" when a device named xremap already exists, escaping
        # Kanata's exact-name exclude list and feeding Kanata its own output.
        ExecStart = "${lib.getExe pkgs.xremap} --watch=device,config --output-device-name xremap --device kanata-oryx --device 'ZSA Technology Labs Voyager Keyboard' ${xremapConfig}";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "sway-session.target" ];
    };

    # =========================================================================
    # swayidle — idle lock, display power-off, and lock before suspend
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
    #
    # The `timeouts` add inactivity handling, lacking before: lock the session
    # after 5 min (so an unattended work laptop doesn't stay open), then power
    # the outputs off two minutes later to save the panel/battery, powering
    # them back on the moment there's activity. Fullscreen windows hold these
    # off via the `inhibit_idle` rules above, so calls/video aren't interrupted.
    services.swayidle = {
      enable = true;
      extraArgs = [ "-w" ];
      timeouts = [
        {
          timeout = 300;
          command = config.my.sway.lockCommand;
        }
        {
          timeout = 420;
          command = "${pkgs.sway}/bin/swaymsg 'output * power off'";
          resumeCommand = "${pkgs.sway}/bin/swaymsg 'output * power on'";
        }
      ];
      events = {
        before-sleep = config.my.sway.lockCommand;
        lock = config.my.sway.lockCommand;
      };
    };

    # =========================================================================
    # dunst — notification daemon (theme-driven)
    # =========================================================================
    # Replaces mako. mako looks up an icon only from a notification's own
    # app_icon field, so apps that send none (Slack sends app_icon="") can never
    # get a logo. dunst can match on the desktop-entry hint and supply an icon
    # via per-app rules (below), so Slack/Zoom get their logos. The module owns
    # org.freedesktop.Notifications via a D-Bus-activated systemd service, so —
    # like mako — it starts on the first notification.
    #
    # iconTheme wires up icon_path to Papirus's per-category dirs at one size:
    # Papirus keeps numeric size dirs (e.g. 48x48/apps/slack.svg) that dunst's
    # name lookup needs, and bundles app-specific logos. Pulled from nixpkgs, so
    # it resolves on peanut (Ubuntu) without depending on distro icon paths.
    services.dunst = {
      enable = true;
      iconTheme = {
        name = "Papirus";
        package = pkgs.papirus-icon-theme;
        size = "48x48";
      };
      settings = {
        global = {
          # Solid accent-coloured card (lime under nebius), no border, with dark
          # text auto-picked for contrast (onAccent) so it stays legible under
          # any theme. Borderless but roomy; separate notifications get their own
          # box via gap_size rather than a divider line.
          background = ui.accent;
          foreground = ui.onAccent;
          frame_width = 0;
          corner_radius = 10;
          padding = 14;
          horizontal_padding = 16;
          gap_size = 8;
          separator_height = 0;
          origin = "top-right";
          # Float the card well clear of the top-right screen corner.
          offset = "(24,24)";
          markup = "full"; # required for the <b> in format to render
          # App name bold on its own line, then summary and body. `\n` is dunst's
          # newline escape in the quoted config value.
          format = "<b>%a</b>\\n%s\\n%b";
        };
        urgency_low.timeout = 5;
        urgency_normal.timeout = 5;
        # Critical flips the card to the urgent colour (red) with auto-contrasted
        # text and never auto-dismisses, matching the bar's urgent state.
        urgency_critical = {
          background = ui.urgent;
          foreground = ui.onUrgent;
          frame_width = 0;
          timeout = 0;
        };
        # Per-app icons for senders that ship none. default_icon only fills in
        # when the notification carries no icon of its own, so it never clobbers
        # a real avatar/image the app might include. Matched on the desktop-entry
        # hint; names resolve against Papirus (48x48/apps/{slack,zoom-desktop}).
        slack = {
          desktop_entry = "Slack"; # verified via dbus-monitor
          default_icon = "slack";
        };
        zoom = {
          desktop_entry = "Zoom"; # best guess — confirm against a real Zoom notification
          default_icon = "zoom-desktop";
        };
        # Slack/calendar/etc. delivered through the browser arrive as Firefox
        # web-push: appname="Firefox", no desktop-entry, no icon (confirmed via
        # dunst history). Badge them with the Firefox logo — the honest "came
        # from the browser" marker, since the notification carries no signal of
        # which site sent it. Matched on appname, the field Firefox actually sets.
        firefox = {
          appname = "Firefox";
          default_icon = "firefox";
        };
        # Terminal/CLI notifications (notify-send & friends) report appname
        # "notify-send" with no icon — the emulator doesn't stamp them, so this
        # is the only handle (confirmed via dunst history). Badge them with the
        # Alacritty logo, the terminal in use. Note this marks ALL notify-send
        # notifications, not only those launched from Alacritty: nothing in the
        # notification identifies the originating terminal.
        terminal = {
          appname = "notify-send";
          default_icon = "Alacritty";
        };
      };
    };

    # =========================================================================
    # sway-autoscale — DPI-based output scaling + placement
    # =========================================================================
    # Runs once at session start and then re-applies on every output hotplug
    # event (dock/undock, plugging a different office monitor). Idempotent:
    # only calls `swaymsg output …` when the computed value differs from the
    # current one, so the output events its own changes trigger converge
    # instead of looping.
    #
    # Besides scaling, arrange() stacks the external output above the laptop
    # panel, horizontally centered, so moving the mouse past eDP's top edge
    # enters the external screen anywhere along it. Positions are derived from
    # live logical sizes, so any monitor on any port works without per-output
    # config.
    systemd.user.services.sway-autoscale =
      let
        cfg = config.my.sway.autoscale;
        # Fixed-scale outputs become case branches ahead of the DPI formula.
        overrideCases = lib.concatStrings (
          lib.mapAttrsToList (name: scale: ''
            ${name}) scale=${scale} ;;
          '') cfg.overrides
        );
        sway-autoscale = pkgs.writeShellApplication {
          name = "sway-autoscale";
          runtimeInputs = [
            pkgs.wlr-randr
            pkgs.jq
            pkgs.gawk
            pkgs.sway # swaymsg
          ];
          text = ''
            apply() {
              wlr-randr --json | jq -c '.[] | select(.enabled)' | while IFS= read -r out; do
                name=$(jq -r '.name' <<<"$out")
                cur=$(jq -r '.scale' <<<"$out")
                px=$(jq -r '[.modes[] | select(.current)][0].width // 0' <<<"$out")
                mm=$(jq -r '.physical_size.width // 0' <<<"$out")

                case "$name" in
                  ${overrideCases}
                  *)
                    # No physical size in EDID (projectors, some TVs): leave alone.
                    if [ "$px" -le 0 ] || [ "$mm" -le 0 ]; then
                      continue
                    fi
                    scale=$(awk -v px="$px" -v mm="$mm" -v t="${toString cfg.targetDpi}" 'BEGIN {
                      dpi = px / (mm / 25.4)
                      s = int(dpi / t * 4 + 0.5) / 4   # round to nearest 0.25
                      if (s < 1) s = 1
                      if (s > 3) s = 3
                      printf "%g", s
                    }')
                    ;;
                esac

                if awk -v a="$cur" -v b="$scale" 'BEGIN { d = a - b; if (d < 0) d = -d; exit (d > 0.01) ? 0 : 1 }'; then
                  echo "$name: ''${px}px / ''${mm}mm -> scale $scale (was $cur)"
                  swaymsg output "$name" scale "$scale"
                fi
              done
            }

            # Stack the first external output above the laptop panel. Reads
            # swaymsg get_outputs rather than wlr-randr because its rects are
            # in logical (post-scale) coordinates — what `output pos` expects —
            # so the offset is right for whatever scale apply() just chose.
            # No-op without an external or without a laptop panel; extra
            # externals keep sway's default placement.
            arrange() {
              outs=$(swaymsg -t get_outputs)
              ext=$(jq -c '[.[] | select(.active and (.name | startswith("eDP") | not))][0] // empty' <<<"$outs")
              edp=$(jq -c '[.[] | select(.active and (.name | startswith("eDP")))][0] // empty' <<<"$outs")
              if [ -z "$ext" ] || [ -z "$edp" ]; then
                return 0
              fi

              ext_name=$(jq -r '.name' <<<"$ext")
              ext_h=$(jq -r '.rect.height' <<<"$ext")
              ext_w=$(jq -r '.rect.width' <<<"$ext")
              edp_name=$(jq -r '.name' <<<"$edp")
              edp_w=$(jq -r '.rect.width' <<<"$edp")
              # Center the panel under the external so the width difference
              # overhangs both sides equally — otherwise the flush corner
              # blocks the pointer from crossing near one edge. Negative x
              # (external narrower than the panel) is fine in sway's layout.
              edp_x=$(( (ext_w - edp_w) / 2 ))

              if [ "$(jq -r '.rect.x' <<<"$ext")" -ne 0 ] || [ "$(jq -r '.rect.y' <<<"$ext")" -ne 0 ]; then
                echo "$ext_name: position 0,0"
                swaymsg output "$ext_name" pos 0 0
              fi
              if [ "$(jq -r '.rect.x' <<<"$edp")" -ne "$edp_x" ] || [ "$(jq -r '.rect.y' <<<"$edp")" -ne "$ext_h" ]; then
                echo "$edp_name: position $edp_x,$ext_h (centered below $ext_name)"
                swaymsg output "$edp_name" pos "$edp_x" "$ext_h"
              fi
            }

            apply
            arrange
            if [ "''${1:-}" = "--watch" ]; then
              swaymsg -t subscribe -m '["output"]' | while IFS= read -r _; do
                sleep 0.5
                apply
                arrange
              done
            fi
          '';
        };
      in
      lib.mkIf cfg.enable {
        Unit = {
          Description = "Set sway output scale and placement from panel geometry";
          PartOf = [ "sway-session.target" ];
          After = [ "sway-session.target" ];
        };
        Service = {
          ExecStart = "${lib.getExe sway-autoscale} --watch";
          Restart = "on-failure";
          RestartSec = 1;
        };
        Install.WantedBy = [ "sway-session.target" ];
      };

    # =========================================================================
    # Sway / Wayland utilities
    # =========================================================================
    home.packages = with pkgs; [
      wl-clipboard # Wayland clipboard (wl-copy / wl-paste)
      grim # Screenshot tool
      slurp # Region selection for screenshots
      swaylock # Screen locker
      nerd-fonts.symbols-only # Icon glyphs for the i3status-rust bar

      # Media-key helpers
      pamixer # Audio volume / mute via pulse/pipewire
      playerctl # MPRIS media control (XF86AudioPlay play/pause)
      brightnessctl # Backlight control via systemd-logind
      wlr-randr # Wayland output config (display switching)
      wdisplays # GUI for output layout (bound to F7 / XF86Display)
      wev # Wayland event viewer — use to discover unknown keysyms

      # Desktop tools
      pavucontrol # PulseAudio volume control (works with PipeWire)
      networkmanagerapplet # Network manager tray applet
    ];

    # Make fonts from home.packages (the Nerd Font symbols above) visible to
    # fontconfig, so swaybar can fall back to them for the bar icons.
    fonts.fontconfig.enable = lib.mkDefault true;
  };
}
