{
  config,
  pkgs,
  inputs,
  outputs,
  ...
}:

{
  # Import shared configurations
  # Note: ../common/users/nima is NixOS-specific, Darwin manages users differently
  imports = [ ../common/core ];

  # ===========================================================================
  # 1Password - Must use nix-darwin module for proper /Applications install
  # ===========================================================================
  programs._1password-gui.enable = true;

  # ===========================================================================
  # Nix Configuration
  # ===========================================================================
  nix.settings = {
    experimental-features = "nix-command flakes";
  };

  # Automatic garbage collection - weekly cleanup
  nix.gc = {
    automatic = true;
    interval = {
      Weekday = 0;
      Hour = 2;
      Minute = 0;
    }; # Sunday at 2 AM
    options = "--delete-older-than 30d";
  };

  # Automatic store optimization
  nix.optimise.automatic = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Note: nix-daemon is managed automatically by nix-darwin when nix.enable is on
  # services.nix-daemon.enable is deprecated and no longer needed

  # ===========================================================================
  # System Metadata
  # ===========================================================================
  # Used for backwards compatibility - update with darwin-rebuild changelog
  system.stateVersion = 6;

  # Set Git commit hash for darwin-version
  system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;

  # Primary user for this system
  system.primaryUser = "nima";

  # Platform
  nixpkgs.hostPlatform = "aarch64-darwin";

  # ===========================================================================
  # System Packages (minimal - most packages in Home Manager)
  # ===========================================================================
  environment.systemPackages = with pkgs; [
    # Infrastructure tools that belong at system level
    podman # Container runtime
    colmena # NixOS deployment tool
  ];

  # ===========================================================================
  # Fonts
  # ===========================================================================
  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

  # ===========================================================================
  # Homebrew Configuration
  # ===========================================================================
  homebrew = {
    enable = true;

    # Command-line tools
    brews = [
      "mas"
      "coreutils"
    ];

    # GUI applications
    casks = [
      "basictex" # LaTeX distribution
      "burp-suite-professional" # Security testing
      "grammarly-desktop" # Writing assistant
      "font-jetbrains-mono" # Font (backup via Homebrew)
      "bambu-studio" # 3D printing slicer
      "qflipper" # Flipper Zero manager
      "lm-studio" # Local LLM management
      "protonvpn" # VPN client
      "inkscape" # Vector graphics editor
    ];

    # Mac App Store applications
    masApps = {
      "ikea desk remote" = 1509037746;
      "1password for safari" = 1569813296;
    };

    # Activation behavior
    onActivation = {
      cleanup = "zap"; # Remove unlisted packages
      autoUpdate = true; # Auto-update Homebrew
      upgrade = true; # Auto-upgrade packages
    };
  };

  # ===========================================================================
  # macOS System Defaults
  # ===========================================================================
  system.defaults = {
    # Dock configuration
    dock = {
      autohide = true;
      autohide-delay = 1000.0;
      orientation = "left";
      show-recents = false;
      tilesize = 24;
      expose-group-apps = true;
      persistent-apps = [ ];
    };

    # Finder configuration
    finder = {
      FXPreferredViewStyle = "clmv"; # Column view
      FXEnableExtensionChangeWarning = false;
      QuitMenuItem = true;
    };

    # Global system preferences
    NSGlobalDomain = {
      AppleICUForce24HourTime = true; # 24-hour time format
      AppleInterfaceStyle = "Dark"; # Dark mode
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
    };

    # Login window
    loginwindow.GuestEnabled = false;
  };

  # ===========================================================================
  # Security Configuration
  # ===========================================================================
  security.pam.services.sudo_local = {
    touchIdAuth = true; # Touch ID for sudo
    watchIdAuth = true; # Apple Watch for sudo
    reattach = true; # Required for tmux/screen sessions
  };

  # ===========================================================================
  # Shell Configuration
  # ===========================================================================
  programs.bash.enable = true;
}
