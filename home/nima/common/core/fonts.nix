{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    nerd-fonts.open-dyslexic
    open-dyslexic
    nerd-fonts.jetbrains-mono
  ];

  fonts.fontconfig.enable = true;
}
