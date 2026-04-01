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
  activeTheme = "tomorrow_night";
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
        size = 18;
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
