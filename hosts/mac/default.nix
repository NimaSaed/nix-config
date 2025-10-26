{ config, pkgs, inputs, outputs, ... }:

{
  # Import shared configurations
  imports = [ ../common/core ../common/users/nima ];

  # Nix configuration
  nix.settings = {
    experimental-features = "nix-command flakes";
    # Optimize storage
    auto-optimise-store = true;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Auto upgrade nix package and the daemon service
  services.nix-daemon.enable = true;

  # Used for backwards compatibility
  system.stateVersion = 5;

  # macOS system defaults
  system.defaults = {
    # Dock settings
    dock = {
      autohide = true;
      orientation = "bottom";
      show-recents = false;
      tilesize = 48;
    };

    # Finder settings
    finder = {
      AppleShowAllExtensions = true;
      FXEnableExtensionChangeWarning = false;
      QuitMenuItem = true;
    };

    # NSGlobalDomain settings
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      # Enable dark mode
      AppleInterfaceStyle = "Dark";
    };
  };

  # macOS-specific packages
  environment.systemPackages = with pkgs;
    [
      # Add macOS-specific tools here
    ];

  # Fonts
  fonts.packages = with pkgs;
    [ (nerdfonts.override { fonts = [ "FiraCode" "JetBrainsMono" ]; }) ];

  # Homebrew integration (optional)
  # Uncomment if you want to manage Homebrew packages via Nix
  # homebrew = {
  #   enable = true;
  #   onActivation.cleanup = "uninstall";
  #   brews = [];
  #   casks = [];
  # };
}
