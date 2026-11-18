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

      selection.save_to_clipboard = true;

      env.TERM = "xterm-256color";

      keyboard.bindings =
        let
          # Nix strings have no \e / \u escapes; borrow JSON's.
          esc = builtins.fromJSON ''"\u001b"'';
        in
        [
          { key = "Return"; mods = "Shift"; chars = "${esc}[13;2u"; }
          { key = "Return"; mods = "Control"; chars = "${esc}[13;5u"; }
        ];

      terminal.shell = {
        program = "${pkgs.bash}/bin/bash";
        args = [ "-l" ];
      };

      colors = config.my.theme;
    };
  };
}
