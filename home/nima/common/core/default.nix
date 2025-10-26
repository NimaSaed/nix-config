{ config, pkgs, ... }:

{
  # Import all core application configurations
  imports = [
    ./git.nix
    ./bash.nix
    ./direnv.nix
    ./starship.nix
    ./bat.nix
    ./eza.nix
    ./zoxide.nix
    ./packages.nix
  ];
}
