{ pkgs, config, lib, ... }:
let
  ifTheyExist = groups:
    builtins.filter (group: builtins.hasAttr group config.users.groups) groups;
in {
  users.mutableUsers = false;
  users.users.nima = {
    initialHashedPassword =
      "$y$j9T$VIgEJ4u79wZRwEny9XepM1$1sYHPUO7bIl5PQtSYE.Ptra8zIFBQyh1AlxKmfAkFg/";
    isNormalUser = true;
    extraGroups = ifTheyExist [ "wheel" "networkmanager" ];

    openssh.authorizedKeys.keys =
      lib.splitString "\n" (builtins.readFile ../../../../home/nima/ssh.pub);
    #packages = [pkgs.home-manager];
    #packages = [inputs.home-manager.packages.${pkgs.system}.default];
  };

  #home-manager.users.nima = import ../../../../home/nima/${config.networking.hostName}.nix;

}
