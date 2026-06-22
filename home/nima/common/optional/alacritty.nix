{
  config,
  pkgs,
  lib,
  ...
}:

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

      # Colours come from the system-wide theme (home/nima/common/core/theme.nix);
      # switch the active palette per host with `my.activeTheme`.
      colors = config.my.theme;
    };
  };
}
