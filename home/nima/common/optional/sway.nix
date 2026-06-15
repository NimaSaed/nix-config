{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Nebius brand palette (see ~/.claude/CLAUDE.md for the full set).
  nebius = {
    deepBlue = "#052B42"; # primary dark / backgrounds
    lime = "#DAFF33"; # primary accent
    violet = "#5D52F6"; # secondary accent — used for urgent states
    lavender = "#C1C1FF"; # soft accent — muted/inactive text
    lightBlue = "#F0F8FF"; # light foreground on dark backgrounds
  };
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

  # Lock command bound to <modifier>+Ctrl+l. Declared as an option so the keybinding
  # can be defined once here while each host overrides only the command when
  # needed — e.g. peanut points it at the system swaylock because the Nix
  # swaylock can't authenticate via PAM on a non-NixOS distro. Hosts that work
  # with the Nix swaylock (NixOS) need to set nothing.
  options.my.sway.lockCommand = lib.mkOption {
    type = lib.types.str;
    default = "${lib.getExe pkgs.swaylock} -f -c ${lib.removePrefix "#" nebius.deepBlue}";
    defaultText = lib.literalExpression ''"''${lib.getExe pkgs.swaylock} -f -c 052B42"'';
    description = "Command bound to <modifier>+l to lock the screen.";
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

        # Solid Nebius deep-blue desktop on every output.
        output."*".bg = "${nebius.deepBlue} solid_color";

        # Window decoration colors. Titlebars are off, so in practice these
        # paint borders and the split indicator: lime marks the focused
        # window, unfocused borders match the background so only gaps
        # separate them, and violet flags urgency.
        colors = {
          focused = {
            border = nebius.lime;
            background = nebius.deepBlue;
            text = nebius.lightBlue;
            indicator = nebius.violet;
            childBorder = nebius.lime;
          };
          focusedInactive = {
            border = nebius.deepBlue;
            background = nebius.deepBlue;
            text = nebius.lavender;
            indicator = nebius.deepBlue;
            childBorder = nebius.deepBlue;
          };
          unfocused = {
            border = nebius.deepBlue;
            background = nebius.deepBlue;
            text = nebius.lavender;
            indicator = nebius.deepBlue;
            childBorder = nebius.deepBlue;
          };
          urgent = {
            border = nebius.violet;
            background = nebius.violet;
            text = nebius.lightBlue;
            indicator = nebius.violet;
            childBorder = nebius.violet;
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
            command = "resize set 50 ppt 70 ppt, move position center";
          }
          {
            criteria.class = "Bitwarden";
            command = "resize set 50 ppt 70 ppt, move position center";
          }
        ];

        # Status bar — deep-blue bar with the focused workspace highlighted
        # in lime (dark text for contrast on the bright background).
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
              background = nebius.deepBlue;
              statusline = nebius.lightBlue;
              separator = nebius.lavender;
              focusedWorkspace = {
                border = nebius.lime;
                background = nebius.lime;
                text = nebius.deepBlue;
              };
              activeWorkspace = {
                border = nebius.deepBlue;
                background = nebius.deepBlue;
                text = nebius.lime;
              };
              inactiveWorkspace = {
                border = nebius.deepBlue;
                background = nebius.deepBlue;
                text = nebius.lavender;
              };
              urgentWorkspace = {
                border = nebius.violet;
                background = nebius.violet;
                text = nebius.lightBlue;
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
            "${mod}+Ctrl+l" = "exec ${config.my.sway.lockCommand}";
            "${mod}+comma" = "move workspace to output left";
            "${mod}+period" = "move workspace to output right";

            # Laptop media-key row. XF86 keysyms only fire on keyboards that
            # have them, so these are harmless on desktops with plain keyboards.
            # pamixer talks to the system PipeWire via the pulse-compat socket;
            # brightnessctl uses logind so no setuid/udev rules needed.
            "XF86AudioMute" = "exec ${pkgs.pamixer}/bin/pamixer -t";
            "XF86AudioLowerVolume" = "exec ${pkgs.pamixer}/bin/pamixer -d 5";
            "XF86AudioRaiseVolume" = "exec ${pkgs.pamixer}/bin/pamixer -i 5";
            "XF86AudioMicMute" = "exec ${pkgs.pamixer}/bin/pamixer --default-source -t";
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
    # The blocks themselves color by state (good/warning/critical), themed to
    # the Nebius palette: lime for good, violet for warning, inverted violet
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
            idle_bg = nebius.deepBlue;
            idle_fg = nebius.lightBlue;
            info_bg = nebius.deepBlue;
            info_fg = nebius.lavender;
            good_bg = nebius.deepBlue;
            good_fg = nebius.lime;
            warning_bg = nebius.deepBlue;
            warning_fg = nebius.violet;
            critical_bg = nebius.violet;
            critical_fg = nebius.lightBlue;
            separator_bg = nebius.deepBlue;
            separator_fg = nebius.lavender;
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
    # sway-autoscale — DPI-based output scaling
    # =========================================================================
    # Runs once at session start and then re-applies on every output hotplug
    # event (dock/undock, plugging a different office monitor). Idempotent:
    # only calls `swaymsg output … scale` when the computed value differs from
    # the current one, so the output events its own changes trigger converge
    # instead of looping.
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

            apply
            if [ "''${1:-}" = "--watch" ]; then
              swaymsg -t subscribe -m '["output"]' | while IFS= read -r _; do
                sleep 0.5
                apply
              done
            fi
          '';
        };
      in
      lib.mkIf cfg.enable {
        Unit = {
          Description = "Set sway output scale from physical panel DPI";
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
      mako # Notification daemon
      fuzzel # Application launcher
      swaylock # Screen locker
      nerd-fonts.symbols-only # Icon glyphs for the i3status-rust bar

      # Media-key helpers
      pamixer # Audio volume / mute via pulse/pipewire
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
