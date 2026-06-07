{
  # system-manager module for peanut (Lenovo P14s Gen 5, work laptop).
  #
  # Ubuntu 24.04 owns the base OS; this only manages a thin slice of system
  # state via system-manager: nix-system-graphics populates /run/opengl-driver
  # so Nix-built GL/Vulkan apps (sway, firefox, ...) use the Intel GPU instead
  # of falling back to software rendering.
  #
  # Apply (root, rarely — only on driver/Mesa updates):
  #   sudo nix run github:numtide/system-manager -- switch --flake '.#peanut'
  #
  # See ./README.md for full laptop setup steps.

  nixpkgs.hostPlatform = "x86_64-linux";

  # Allow running system-manager on a non-NixOS distro (Ubuntu).
  system-manager.allowAnyDistro = true;

  # Provide system-wide graphics drivers for Nix apps (Intel Mesa by default).
  system-graphics.enable = true;
}
