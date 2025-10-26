{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # System utilities
    htop
    btop
    tree
    wget
    curl

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
    dig

    # Development tools
    vim
    neovim
    git

    # Nix tools
    nixfmt-classic
    nil # Nix LSP
  ];
}
