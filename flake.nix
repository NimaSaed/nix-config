{
  description = "My Personal Nix Flake";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";

    # Home manager
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    ...
  } @ inputs: let
    inherit (self) outputs;

  in {

    nixosConfigurations = {

      # vm for testing nixos
      vm = nixpkgs.lib.nixosSystem {
        modules = [ ./hosts/vm ];
        specialArgs = {
          inherit inputs outputs;
        };
      };

    };
    #homeConfigurations = {
    #  "nima@vm" = home-manager.lib.homeManagerConfiguration {
    #        pkgs = nixpkgs.legacyPackages."x86_64-linux";
    #        extraSpecialArgs = {inherit inputs outputs;};
    #        modules = [./home/nima/vm.nix];
    #      };
    #};
  };
}
