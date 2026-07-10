{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Teleport-issued SSH credentials for the company GitLab. `tsh login` writes
  # these under ~/.tsh; the SSH cert is short-lived (~11h), so the Match exec
  # below refreshes it on demand before git connects. The login is the local
  # username plus the corporate domain (matches the SSO identity).
  tshKey = "${config.home.homeDirectory}/.tsh/keys/bastion.man.nebiusinfra.net/nima@nebius.com";

  sway-lid-close = pkgs.writeShellApplication {
    name = "sway-lid-close";
    runtimeInputs = [
      pkgs.jq
      pkgs.sway
    ];
    text = ''
      external_outputs=$(swaymsg -t get_outputs | jq '[.[] | select(.active and .name != "eDP-1")] | length')

      if [ "$external_outputs" -gt 0 ]; then
        swaymsg output eDP-1 disable
      else
        ${config.my.sway.lockCommand}
      fi
    '';
  };
in
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
    ./common/optional/pipewire.nix
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

  # Declarative audio device preference. WirePlumber makes the default sink/
  # source the highest priority.session among nodes currently present, so the
  # desired setups fall out of one ordering (media keys and the bar's sound
  # blocks always act on the default, so they follow along):
  #   - undocked:            Speaker (1000) and internal mic (1648) win
  #   - headphones in the 3.5mm jack (work): the UCM config models Speaker
  #     and Headphones as mutually exclusive card profiles; a custom Lua
  #     hook follows the jack (see sof-jack-profile.lua below)
  #   - Blue Yeti on USB (home): Yeti monitor jack (1200) beats Speaker,
  #     Yeti mic (2200) beats internal mic
  # The Yeti values pin what stock heuristics happen to assign today (1109 /
  # 2108), so the home setup keeps working if upstream reshuffles. The last
  # rule is the 3.5mm jack mic — matched under both UCM namings (Mic2 with
  # nixpkgs UCM, plain hw_sofhdadsp with Ubuntu's) — demoted below the
  # internal mic (1648) so plugging a 4-pole headset cable never silently
  # steals the default mic.
  #
  # A manual pick (wpctl set-default / pavucontrol) still overrides this via
  # ~/.local/state/wireplumber/default-nodes until the picked node vanishes.
  xdg.configFile."wireplumber/wireplumber.conf.d/51-peanut-device-priorities.conf".text = ''
    monitor.alsa.rules = [
      {
        matches = [
          { node.name = "~alsa_output.usb-Generic_Blue_Microphones.*" }
        ]
        actions = { update-props = { priority.session = 1200 } }
      }
      {
        matches = [
          { node.name = "~alsa_input.usb-Generic_Blue_Microphones.*" }
        ]
        actions = { update-props = { priority.session = 2200 } }
      }
      {
        matches = [
          { node.name = "alsa_input.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Mic2__source" }
          { node.name = "alsa_input.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__hw_sofhdadsp__source" }
        ]
        actions = { update-props = { priority.session = 1500 } }
      }
    ]

    wireplumber.components = [
      {
        name = sof-jack-profile.lua
        type = script/lua
        provides = custom.sof-jack-profile
      }
    ]
    wireplumber.profiles = {
      main = {
        custom.sof-jack-profile = required
      }
    }
  '';

  # Follow the 3.5mm headphone jack across sof-hda-dsp's split UCM profiles.
  # alsa-ucm-conf >= 1.2.11 models Speaker and Headphones as two mutually
  # exclusive card profiles, and both always report "available" (each also
  # contains the HDMI ports), so neither WirePlumber's availability-based
  # profile selection nor ACP's api.acp.auto-profile ever switches on jack
  # events — PulseAudio's module-switch-on-port-available has no PipeWire
  # equivalent (verified empirically 2026-07-03; upstream:
  # https://github.com/alsa-project/alsa-ucm-conf/issues/720 and /728).
  # What DOES flip reliably on plug/unplug is the availability of the
  # "[Out] Headphones" route, so this hook keys on that and re-asserts the
  # matching profile. It also self-corrects after WirePlumber's stored-
  # profile restore at startup (any Profile change re-triggers it, and it
  # no-ops once the profile matches the jack). Delete when upstream learns
  # to do this natively.
  xdg.dataFile."wireplumber/scripts/sof-jack-profile.lua".text = ''
    cutils = require ("common-utils")
    log = Log.open_topic ("s-sof-jack")

    local CARD = "alsa_card.pci-0000_00_1f.3-platform-skl_hda_dsp_generic"

    -- the two analog HiFi profiles, distinguished by which device they carry
    local function findProfile (device, want_headphones)
      for p in device:iterate_params ("EnumProfile") do
        local prof = cutils.parseParam (p, "EnumProfile")
        if prof and prof.name:find ("HiFi", 1, true) then
          if (prof.name:find ("Headphones", 1, true) ~= nil) == want_headphones then
            return prof
          end
        end
      end
      return nil
    end

    local function sync (device)
      local hp_available = nil
      for p in device:iterate_params ("EnumRoute") do
        local route = cutils.parseParam (p, "EnumRoute")
        if route and route.name == "[Out] Headphones" then
          hp_available = (route.available == "yes")
        end
      end
      if hp_available == nil then
        return
      end

      local active = nil
      for p in device:iterate_params ("Profile") do
        active = cutils.parseParam (p, "Profile")
      end
      -- only move between the two HiFi profiles; leave Off / Pro Audio /
      -- other manual choices alone
      if not active or not active.name:find ("HiFi", 1, true) then
        return
      end

      local target = findProfile (device, hp_available)
      if not target or target.index == active.index then
        return
      end

      log:info (device, string.format ("headphone jack %s -> profile '%s'",
          hp_available and "plugged" or "unplugged", target.name))
      device:set_param ("Profile", Pod.Object {
        "Spa:Pod:Object:Param:Profile", "Profile",
        index = target.index,
      })
    end

    SimpleEventHook {
      name = "sof-jack-profile-switch",
      interests = {
        EventInterest {
          Constraint { "event.type", "=", "device-added" },
          Constraint { "device.name", "=", CARD },
        },
        EventInterest {
          Constraint { "event.type", "=", "device-params-changed" },
          Constraint { "event.subject.param-id", "c", "EnumRoute" },
          Constraint { "device.name", "=", CARD },
        },
        EventInterest {
          Constraint { "event.type", "=", "device-params-changed" },
          Constraint { "event.subject.param-id", "c", "Profile" },
          Constraint { "device.name", "=", CARD },
        },
      },
      execute = function (event)
        sync (event:get_subject ())
      end
    }:register ()
  '';

  # List only Nix-installed apps in the launcher. fuzzel scans every
  # applications dir on XDG_DATA_DIRS; on Ubuntu that pulls in ~80 distro
  # entries, many of which don't work under sway. Point fuzzel's scan at just
  # the Nix profile (XDG_DATA_HOME is still read, e.g. for the Yazi launcher),
  # and use --launch-prefix to restore the full XDG_DATA_DIRS for whatever it
  # launches so those apps keep system icons/schemas. Anything I actually want
  # in the launcher gets installed via Nix.
  wayland.windowManager.sway.config.menu =
    let
      fuzzel-nix = pkgs.writeShellScript "fuzzel-nix-apps" ''
        full="$XDG_DATA_DIRS"
        export XDG_DATA_DIRS="$HOME/.nix-profile/share"
        exec ${lib.getExe pkgs.fuzzel} --launch-prefix="${pkgs.coreutils}/bin/env XDG_DATA_DIRS=$full "
      '';
    in
    "${fuzzel-nix}";

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
  # screen is viewed up close, smaller text is fine: pin 1.15 (logical
  # 1536x960). External monitors (home LG 4K, whatever the office dock has)
  # keep the automatic physical-size-based scale.
  my.sway.autoscale.overrides."eDP-1" = "1.15";

  # ThinkPad F12 "star" key — emits XF86Favorites. Toggle media play/pause.
  # playerctl talks MPRIS over D-Bus, so it controls whatever player is
  # active (Firefox, Spotify, mpv, …). `mkOptionDefault` is essential —
  # without it this definition would have higher priority than the shared
  # bindings (which use mkOptionDefault) and clobber every other keybinding,
  # including sway's built-in defaults.
  wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault {
    "XF86Favorites" = "exec ${lib.getExe pkgs.playerctl} play-pause";
  };

  # Clamshell mode: when docked, disable the built-in panel on lid close so
  # windows move to the external monitor (which becomes primary). When undocked,
  # lock immediately and let logind suspend; disabling eDP-1 before suspend can
  # leave a short unlocked-looking flash while the panel is re-enabled on wake.
  # --locked keeps the reopen path working over the lock screen; --reload
  # re-applies the state on config reload. eDP-1 is the laptop panel (see
  # autoscale override above).
  wayland.windowManager.sway.extraConfig = ''
    bindswitch --reload --locked lid:on exec ${lib.getExe sway-lid-close}
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

    # Power management CLI. The boot-time `--auto-tune` runs as a root systemd
    # service in system-manager (hosts/peanut/default.nix), since auto-tune
    # writes /sys power knobs that home-manager's unprivileged user services
    # can't touch. This package is just for interactive use (`sudo powertop`).
    powertop

    # Dev tools
    github-cli
    teleport # `tsh` — mints short-lived SSH certs for the company GitLab via the Teleport bastion
  ];

  # ===========================================================================
  # Program Configurations
  # ===========================================================================
  # `tsh` loads its minted SSH key into $SSH_AUTH_SOCK by default, but that
  # socket is the Bitwarden agent (bitwarden-ssh-agent.nix), which rejects
  # external key additions ("agent: failure"). We read the Teleport cert off
  # disk in the SSH match block below, so the agent isn't needed — opt out of
  # loading into it for every tsh invocation. The match exec also passes
  # --no-use-local-ssh-agent so the auto-relogin path is covered regardless of
  # how the environment is set up.
  home.sessionVariables.TELEPORT_USE_LOCAL_SSH_AGENT = "false";

  programs = {
    home-manager.enable = true;

    # Commit as my corporate identity in company repos. The global git config
    # (home/nima/common/core/git.nix) uses my personal nima@nmsd.xyz — including
    # for this nix-config repo — so this can't be set globally. Scope it to any
    # repo whose remote is on gitlab.nebius.dev via a conditional include keyed
    # on the remote URL, so it applies wherever the repo is cloned. The `*/**`
    # pattern is required to span the group/repo path: plain `*` (and a bare
    # `**` right after the `:`) won't cross the slash, but `*/**` does — verified
    # against single-level and nested-subgroup SSH remotes.
    git.includes = [
      {
        condition = "hasconfig:remote.*.url:git@gitlab.nebius.dev:*/**";
        contents.user.email = "nima@nebius.com";
      }
    ];

    # Company GitLab over SSH, authenticated through Teleport. Cloning/pushing
    # gitlab.nebius.dev doesn't use a long-lived key — the Match exec runs
    # `tsh login` (the teleport package above) whenever the cached cert is
    # older than 11h, minting a fresh short-lived SSH certificate that git then
    # uses. `identitiesOnly` restricts auth to these cert files, so the global
    # Bitwarden IdentityAgent (bitwarden-ssh-agent.nix) is bypassed for this
    # host. Peanut-only: that shared agent module is also used by hazelnut.
    ssh.matchBlocks."gitlab.nebius.dev" = {
      match = ''Host gitlab.nebius.dev exec "find ${tshKey}-ssh -mmin +660 -exec false {} + || $(which tsh) login --no-use-local-ssh-agent --proxy=bastion.man.nebiusinfra.net:443 bastion-man; echo -n"'';
      identityFile = tshKey;
      certificateFile = "${tshKey}-ssh/bastion-man-cert.pub";
      identitiesOnly = true;
      user = "git";
      extraOptions.PreferredAuthentications = "publickey";
    };
  };
}
