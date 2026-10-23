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

      # Alacritty would default to TERM=alacritty, but hosts without that
      # terminfo (anything SSH'd into from outside tmux) then get broken
      # clear/vim.  xterm-256color is universal and Alacritty is
      # xterm-compatible; truecolor still works via COLORTERM=truecolor.  It
      # also lets the `xterm*:extkeys` terminal-feature in tmux.nix match.
      env.TERM = "xterm-256color";

      # Shift+Enter / Ctrl+Enter as distinct keys in TUIs (pi, claude) under
      # tmux.
      #
      # Alacritty only implements the kitty keyboard protocol, while tmux 3.6
      # only asks the outer terminal for xterm modifyOtherKeys (`CSI > 4;2 m`),
      # so the two never negotiate and both chords degrade to a plain Enter.
      # Send the CSI-u encoding directly: tmux parses it unconditionally and
      # forwards it to panes that have requested extended keys; other panes
      # still receive a plain Enter, as before.
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

      # Colours come from the system-wide theme (home/nima/common/core/theme.nix);
      # switch the active palette per host with `my.activeTheme`.
      colors = config.my.theme;
    };
  };
}
