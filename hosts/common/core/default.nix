{ pkgs, ... }:
{
  # Nix configuration
  nix.settings = {
    experimental-features = "nix-command flakes";
  };

  # System-level packages
  # Keep this minimal - most packages should be in home-manager (home/nima/common/core/packages.nix)
  # Only include packages that are:
  #   - Needed by system services
  #   - Required before user login
  #   - Critical for system recovery
  environment.systemPackages = with pkgs; [
    # Add system-critical packages here if needed
    # Most CLI tools should go in home-manager instead
  ];
}
