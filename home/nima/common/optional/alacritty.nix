{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Define themes inline - switch by changing `activeTheme`
  themes = {
    solarized_light = {
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

  # Change this to switch themes
  activeTheme = "nebius";
in
{
  programs.alacritty = {
    enable = true;

    settings = {
      window = {
        padding = {
          x = 25;
          y = 25;
        };
        opacity = 1;
        blur = false;
        decorations = "Buttonless";
        option_as_alt = "Both";
      };

      font = {
        size = 14;
        normal = {
          family = "OpenDyslexicM Nerd Font Mono";
          style = "Regular";
        };
        bold = {
          family = "OpenDyslexicM Nerd Font Mono";
          style = "Bold";
        };
        italic = {
          family = "OpenDyslexicM Nerd Font Mono";
          style = "Italic";
        };
        bold_italic = {
          family = "OpenDyslexicM Nerd Font Mono";
          style = "Bold Italic";
        };
        # Negative values reduce spacing; y = line spacing, x = letter spacing
        offset = {
          x = -4;
          y = -12;
        };
      };

      cursor = {
        blink_interval = 500;
        blink_timeout = 0;
        unfocused_hollow = false;
        style = {
          shape = "Block";
          blinking = "Always";
        };
      };

      mouse.hide_when_typing = true;

      terminal.shell = {
        program = "${pkgs.bash}/bin/bash";
        args = [ "-l" ];
      };

      # Inline colors from selected theme
      colors = themes.${activeTheme};
    };
  };
}
