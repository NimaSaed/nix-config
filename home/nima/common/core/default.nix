{ config, pkgs, ... }:

{
  # Import all core application configurations
  imports = [
    ./theme.nix
    ./git.nix
    ./bash.nix
    ./tmux.nix
    ./direnv.nix
    ./bat.nix
    ./eza.nix
    ./zoxide.nix
    ./packages.nix
    ./vim.nix
  ];
}
