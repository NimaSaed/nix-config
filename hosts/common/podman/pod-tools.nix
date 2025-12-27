{ config, lib, pkgs, ... }:

{
  home-manager.users.poddy = { pkgs, config, ... }: {
    virtualisation.quadlet = let
      inherit (config.virtualisation.quadlet) networks;
    in {
      pods.tools = {
        podConfig = {
          networks = [ networks.reverse_proxy.ref ];
          publishPorts = [
            "3000:3000"
          ];
        };
      };
    };
  };
}
