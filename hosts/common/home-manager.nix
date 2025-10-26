{ config, lib, pkgs, inputs, ... }:

{
  # Shared home-manager configuration module
  # This module provides common home-manager settings across all hosts

  home-manager = {
    # Use global pkgs instance
    useGlobalPkgs = true;

    # Install packages to /etc/profiles instead of ~/.nix-profile
    useUserPackages = true;

    # Pass extra arguments to home-manager modules
    extraSpecialArgs = { inherit inputs; };
  };
}
