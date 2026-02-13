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
  };

  # Change this to switch themes
  activeTheme = "solarized_light";
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
          family = "JetBrainsMono Nerd Font Mono";
          style = "Regular";
        };
        bold = {
          family = "JetBrainsMono Nerd Font Mono";
          style = "Bold";
        };
        italic = {
          family = "JetBrainsMono Nerd Font Mono";
          style = "Italic";
        };
        bold_italic = {
          family = "JetBrainsMono Nerd Font Mono";
          style = "Bold Italic";
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
