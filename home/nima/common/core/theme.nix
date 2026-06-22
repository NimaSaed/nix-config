{ lib, config, ... }:

let
  # ===========================================================================
  # System-wide colour themes
  # ===========================================================================
  # Single source of truth for colours. Palettes are terminal-shaped
  # (cursor/primary/selection/normal/bright) so alacritty can consume one
  # directly (config.my.theme), while sway, dunst and firefox use the derived
  # semantic UI map (config.my.ui). Pick the active palette per host with
  # `my.activeTheme` (e.g. peanut → nebius, hazelnut → solarized_dark).
  themes = {
    solarized_light = {
      polarity = "light";
      cursor = {
        text = "#ffffff";
        cursor = "#586e75";
      };
      primary = {
        background = "#fdf6e3";
        foreground = "#586e75";
      };
      normal = {
        black = "#fdf6e3";
        red = "#dc322f";
        green = "#859900";
        yellow = "#b58900";
        blue = "#268bd2";
        magenta = "#6c71c4";
        cyan = "#2aa198";
        white = "#657b83";
      };
      bright = {
        black = "#93a1a1";
        red = "#b52828";
        green = "#677300";
        yellow = "#8f6400";
        blue = "#2272ab";
        magenta = "#545f9e";
        cyan = "#d33682";
        white = "#002b36";
      };
    };

    solarized_dark = {
      polarity = "dark";
      cursor = {
        text = "#ffffff";
        cursor = "#586e75";
      };
      primary = {
        background = "#002b36";
        foreground = "#93a1a1";
      };
      normal = {
        black = "#002b36";
        red = "#dc322f";
        green = "#859900";
        yellow = "#b58900";
        blue = "#268bd2";
        magenta = "#6c71c4";
        cyan = "#2aa198";
        white = "#93a1a1";
      };
      bright = {
        black = "#657b83";
        red = "#b52828";
        green = "#677300";
        yellow = "#8f6400";
        blue = "#2272ab";
        magenta = "#545f9e";
        cyan = "#d33682";
        white = "#fdf6e3";
      };
    };

    # Nebius brand theme
    # Stars: Deep Blue #052B42 (bg), Lime #DAFF33 (cursor + full yellow channel),
    # Light Blue #F0F8FF (text). Lavender #C1C1FF / Violet #5D52F6 support;
    # red/green/cyan harmonized but kept functional for diffs & syntax.
    nebius = {
      polarity = "dark";
      cursor = {
        text = "#052B42";
        cursor = "#DAFF33";
      };
      primary = {
        background = "#052B42";
        foreground = "#F0F8FF";
      };
      selection = {
        text = "#052B42";
        background = "#C1C1FF";
      };
      normal = {
        black = "#0E3B54";
        red = "#E06C75";
        green = "#98C379";
        yellow = "#D6F34C";
        blue = "#8B83FF";
        magenta = "#B589F0";
        cyan = "#56B6C2";
        white = "#C1C1FF";
      };
      bright = {
        black = "#3E6E8E";
        red = "#FF8389";
        green = "#B5E890";
        yellow = "#DAFF33";
        blue = "#C1C1FF";
        magenta = "#CBB2FF";
        cyan = "#79D0DC";
        white = "#F0F8FF";
      };
    };

    tomorrow_night = {
      polarity = "dark";
      cursor = {
        text = "#1d1f21";
        cursor = "#c5c8c6";
      };
      primary = {
        background = "#1d1f21";
        foreground = "#c5c8c6";
      };
      normal = {
        black = "#282a2e";
        red = "#a54242";
        green = "#8c9440";
        yellow = "#de935f";
        blue = "#5f819d";
        magenta = "#85678f";
        cyan = "#5e8d87";
        white = "#707880";
      };
      bright = {
        black = "#373b41";
        red = "#cc6666";
        green = "#b5bd68";
        yellow = "#f0c674";
        blue = "#81a2be";
        magenta = "#b294bb";
        cyan = "#8abeb7";
        white = "#c5c8c6";
      };
    };
  };

  # --- Contrast helper -------------------------------------------------------
  # Pick a legible ink for text on a coloured box, choosing dark or light from
  # the active theme's own extremes by luminance — so accent/urgent boxes stay
  # readable in every theme (light accents get dark text, dark accents light).
  hexDigit = {
    "0" = 0; "1" = 1; "2" = 2; "3" = 3; "4" = 4; "5" = 5; "6" = 6; "7" = 7;
    "8" = 8; "9" = 9; a = 10; b = 11; c = 12; d = 13; e = 14; f = 15;
    A = 10; B = 11; C = 12; D = 13; E = 14; F = 15;
  };
  hexToInt = s: lib.foldl' (acc: ch: acc * 16 + hexDigit.${ch}) 0 (lib.stringToCharacters s);
  luminance =
    color:
    let
      h = lib.removePrefix "#" color;
      r = hexToInt (builtins.substring 0 2 h);
      g = hexToInt (builtins.substring 2 2 h);
      b = hexToInt (builtins.substring 4 2 h);
    in
    (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
in
{
  options.my = {
    activeTheme = lib.mkOption {
      type = lib.types.enum (lib.attrNames themes);
      default = "tomorrow_night";
      description = "System-wide colour theme. Consumed by alacritty, sway, dunst and firefox. Override per host.";
    };
    theme = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      description = "The terminal-shaped colour palette selected by my.activeTheme (alacritty consumes this directly).";
    };
    polarity = lib.mkOption {
      type = lib.types.enum [
        "dark"
        "light"
      ];
      readOnly = true;
      description = "Whether the active theme is dark or light; picks light/dark UI variants (e.g. the firefox base theme).";
    };
    ui = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      description = "Semantic UI colours derived from my.theme; consumed by sway, dunst and firefox.";
    };
  };

  config.my = {
    # Strip the polarity tag so alacritty/my.ui see only colour groups.
    theme = builtins.removeAttrs themes.${config.my.activeTheme} [ "polarity" ];
    polarity = themes.${config.my.activeTheme}.polarity;

    ui =
      let
        palette = config.my.theme;
        inks =
          if luminance palette.primary.background < luminance palette.primary.foreground then
            {
              dark = palette.primary.background;
              light = palette.primary.foreground;
            }
          else
            {
              dark = palette.primary.foreground;
              light = palette.primary.background;
            };
        onColor = bg: if luminance bg > 0.5 then inks.dark else inks.light;
      in
      {
        surface = palette.primary.background; # window/bar/chrome background
        surfaceAlt = palette.normal.black; # lifted surface (fields, tabs)
        onSurface = palette.primary.foreground; # primary text on the surface
        accent = palette.bright.yellow; # focused/active/good highlight
        onAccent = onColor palette.bright.yellow; # legible text on an accent box
        muted = palette.normal.white; # inactive/secondary text
        urgent = palette.normal.red; # urgent/critical (replaces brand violet)
        onUrgent = onColor palette.normal.red; # legible text on an urgent box
        indicator = palette.normal.blue; # secondary accent (split indicator)
      };
  };
}
