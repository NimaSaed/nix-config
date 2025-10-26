{ config, pkgs, ... }:

{
  # Import all core application configurations
  imports = [
    ./git.nix
    ./bash.nix
    ./tmux.nix
    ./direnv.nix
    ./bat.nix
    ./eza.nix
    ./zoxide.nix
    ./packages.nix
  ];
}
