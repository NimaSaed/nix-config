{ config, pkgs, lib, ... }:

{
  programs.tmux = {
    enable = true;

    # Use screen-256color for better color support
    terminal = "screen-256color";

    # Start window and pane numbering at 1 (0 is too far!)
    baseIndex = 1;

    # Vi mode keybindings
    keyMode = "vi";

    # Mouse support
    mouse = true;

    # Increase history limit significantly
    historyLimit = 10000000;

    # Custom configuration
    extraConfig = ''
      # =========================================================================
      # Vi Copy Mode Settings
      # =========================================================================
      set-window-option -g mode-keys vi

      # Setup 'v' to begin selection as in Vim
      bind-key -T copy-mode-vi 'v' send -X begin-selection

      # Platform-specific clipboard integration
      ${if pkgs.stdenv.isDarwin then ''
        # macOS - use pbcopy
        bind-key -T copy-mode-vi 'y' send -X copy-pipe-and-cancel "reattach-to-user-namespace pbcopy"
      '' else ''
        # Linux - use xclip
        bind-key -T copy-mode-vi 'y' send -X copy-pipe-and-cancel 'xclip -in -selection clipboard'
      ''}

      # =========================================================================
      # Pane Styling
      # =========================================================================
      set -g pane-border-style fg=colour15
      set -g pane-active-border-style fg=colour1

      # =========================================================================
      # Status Bar Configuration
      # =========================================================================
      set-option -g status-style bg=default
      set-option -g status-style fg=default
      set -g status-left '''
      set -g status-right '''
      set -g status-interval 0
      set-option -g status-position bottom

      # =========================================================================
      # Key Bindings
      # =========================================================================

      # Reload tmux config
      bind r source-file ~/.tmux.conf

      # Clear history
      bind-key L clear-history

      # Move pane to other windows
      bind m command-prompt "move-pane -t ':%%'"

      # Move window
      bind M command-prompt "move-window -t ':%%'"

      # Open new pane in current path
      bind '"' split-window -v -c "#{pane_current_path}"
      bind % split-window -h -c "#{pane_current_path}"

      # Use vim-like keys for splits and windows
      bind-key v split-window -h -c "#{pane_current_path}"
      bind-key s split-window -v -c "#{pane_current_path}"

      # =========================================================================
      # Vim-Style Pane Navigation
      # =========================================================================
      bind-key h select-pane -L
      bind-key j select-pane -D
      bind-key k select-pane -U
      bind-key l select-pane -R

      # =========================================================================
      # Vim-Style Pane Resizing
      # =========================================================================
      unbind-key C-h
      unbind-key C-j
      unbind-key C-k
      unbind-key C-l
      bind-key C-h resize-pane -L 5
      bind-key C-j resize-pane -D 5
      bind-key C-k resize-pane -U 5
      bind-key C-l resize-pane -R 5

      # =========================================================================
      # Quick Pane Selection (1-4)
      # =========================================================================
      set -g pane-base-index 1
      bind-key C-q select-pane -t 1
      bind-key C-w select-pane -t 2
      bind-key C-e select-pane -t 3
      bind-key C-r select-pane -t 4

      # =========================================================================
      # Shell Configuration
      # =========================================================================
      set-option -g default-shell ${pkgs.bash}/bin/bash
    '';
  };
}
