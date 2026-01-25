{ config, pkgs, ... }:

{
  home.packages =
    with pkgs;
    [
      # System utilities
      htop
      btop
      tree
      wget
      curl
      tmux

      # File search and manipulation
      ripgrep # Better grep
      fd # Better find
      fzf # Fuzzy finder

      # Data processing
      jq # JSON processor
      yq # YAML processor

      # Archive tools
      unzip
      zip
      gnutar

      # Network tools
      nmap
      dnsutils # dig
      bind # Additional DNS tools

      # Development tools
      git

      # Nix tools
      nil # Nix LSP

      # Bash configuration dependencies
      coreutils # For gdircolors (macOS) and other GNU tools
      util-linux # For colrm and other utilities (Linux)
      awscli2 # AWS CLI v2 for AWS functions

      # macOS-specific (conditionally included)
    ]
    ++ (
      if pkgs.stdenv.isDarwin then
        [
          reattach-to-user-namespace # For tmux clipboard on macOS
        ]
      else
        [ ]
    );
}
