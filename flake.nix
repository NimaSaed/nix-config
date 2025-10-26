{
  description = "My Personal Nix Flake";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";

    # Home manager
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Disko for declarative disk management
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Colmena for remote deployment
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    disko,
    nixpkgs,
    home-manager,
    ...
  } @ inputs: let
    inherit (self) outputs;

  in {

    nixosConfigurations = {

      # vm for testing nixos
      vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/vm
          inputs.disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.nima = import ./home/nima/vm.nix;
          }
        ];
        specialArgs = {
          inherit inputs outputs;
        };
      };
    };

    # Colmena deployment configuration
    colmena = {
      meta = {
        nixpkgs = import nixpkgs {
          system = "x86_64-linux";
        };
        specialArgs = {
          inherit inputs outputs;
        };
      };

      # Production server deployment
      server = {
        deployment = {
          targetHost = "192.168.1.94";
          targetUser = "root";
          buildOnTarget = true; # Build on server instead of locally
          tags = [ "production" "server" ];
        };

        imports = [
          ./hosts/server
          inputs.disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.nima = import ./home/nima/server.nix;
          }
        ];
      };
    };
  };
}
