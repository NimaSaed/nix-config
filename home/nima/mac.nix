{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Import shared core configurations
  imports = [ ./common/core ];

  # ===========================================================================
  # Home Manager Settings
  # ===========================================================================
  home = {
    username = "nima";
    # mkForce needed because home-manager's nixos/common.nix sets a default based on
    # users.users.<name>.home which doesn't exist on Darwin
    homeDirectory = lib.mkForce "/Users/nima";
    stateVersion = "26.05";
  };

  # ===========================================================================
  # macOS-Specific Packages
  # ===========================================================================
  # Note: Common packages (git, vim, jq, yq, bat, fzf, ripgrep, fd, etc.)
  # are already included via ./common/core/packages.nix
  home.packages = with pkgs; [
    # Development Tools
    nodejs_22 # Node.js runtime
    claude-code # Anthropic's CLI tool
    opencode # Code editor
    openfga # Authorization framework
    openfga-cli # OpenFGA CLI
    pandoc # Document converter
    mkdocs # Documentation generator
    semgrep # Code security scanning
    openscad # 3D CAD software
    gnused # GNU sed (macOS sed is BSD)

    # Desktop Applications
    alacritty # Terminal emulator
    aerospace # Window manager for macOS
    brave # Web browser
    monitorcontrol # External monitor controls
    zoom-us # Video conferencing
    _1password-cli # 1Password CLI (GUI installed via nix-darwin)
  ];

  # ===========================================================================
  # Program Configurations
  # ===========================================================================
  programs = {
    # Enable home-manager
    home-manager.enable = true;
  };

  # ===========================================================================
  # Environment Variables
  # ===========================================================================
  home.sessionVariables = {
    # Ensure Homebrew paths are available
    HOMEBREW_PREFIX = "/opt/homebrew";
  };
}
