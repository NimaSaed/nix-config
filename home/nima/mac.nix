{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Import shared core configurations
  imports = [
    ./common/core
    ./common/core/fonts.nix
    ./common/optional/alacritty.nix
    ./common/optional/claude-code.nix
    ./common/optional/aerospace.nix
    ./common/optional/bitwarden.nix
    ./common/optional/bitwarden-ssh-agent.nix
    ./common/optional/firefox.nix
  ];

  # ===========================================================================
  # Home Manager Settings
  # ===========================================================================
  home = {
    username = "nima";
    # mkForce needed because home-manager's nixos/common.nix sets a default based on
    # users.users.<name>.home which doesn't exist on Darwin
    homeDirectory = lib.mkForce "/Users/nima";
    stateVersion = "25.11";
  };

  # ===========================================================================
  # macOS-Specific Packages
  # ===========================================================================
  # Note: Common packages (git, vim, jq, yq, bat, fzf, ripgrep, fd, etc.)
  # are already included via ./common/core/packages.nix
  home.packages = with pkgs; [
    # Development Tools
    nodejs_22 # Node.js runtime
    unstable.opencode # Code editor
    openfga # Authorization framework
    openfga-cli # OpenFGA CLI
    pandoc # Document converter
    #mkdocs # Documentation generator
    (python3.withPackages (
      ps: with ps; [
        mkdocs-material
        pymdown-extensions
        # add other extensions here
      ]
    ))
    semgrep # Code security scanning
    openscad # 3D CAD software
    gnused # GNU sed (macOS sed is BSD)

    # Note: bw-sops-key helper comes from ./common/optional/bitwarden.nix

    # Desktop Applications (alacritty configured via programs.alacritty)
    aerospace # Window manager for macOS
    brave # Web browser
    monitorcontrol # External monitor controls
    #zoom-us # Video conferencing
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
  # Bitwarden SSH agent (SSH_AUTH_SOCK + programs.ssh) comes from
  # ./common/optional/bitwarden-ssh-agent.nix
}
