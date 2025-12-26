{
  description = "Nima's Personal Nix Configuration";

  # ============================================================================
  # Flake Inputs - External dependencies and their sources
  # ============================================================================
  inputs = {
    # Nixpkgs - The main package repository (stable branch)
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";

    # Home Manager - Declarative user environment management
    # Follows nixpkgs version to ensure compatibility
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # nix-darwin - macOS system configuration management
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Disko - Declarative disk partitioning and formatting
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Colmena - NixOS deployment tool for remote machines
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nixos-generators - Tool for generating various NixOS image formats
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # sops-nix - Secrets management with SOPS (Secrets OPerationS)
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # quadlet-nix - Declarative Podman Quadlet configuration for NixOS
    # Enables managing rootless containers via systemd with proper permissions
    quadlet-nix = { url = "github:SEIAROTg/quadlet-nix"; };
  };

  # ============================================================================
  # Flake Outputs - What this flake provides
  # ============================================================================
  outputs = { self, disko, nixpkgs, home-manager, darwin, nixos-generators
    , sops-nix, quadlet-nix, ... }@inputs:
    let inherit (self) outputs;

    in {
      # -------------------------------------------------------------------------
      # Formatter - Format Nix files with `nix fmt`
      # -------------------------------------------------------------------------
      formatter = {
        x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-classic;
        aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt-classic;
      };

      # -------------------------------------------------------------------------
      # Reusable NixOS Modules - Can be imported by other flakes
      # -------------------------------------------------------------------------
      nixosModules = {
        default = ./hosts/common/home-manager.nix;
        home-manager = ./hosts/common/home-manager.nix;
      };

      # -------------------------------------------------------------------------
      # Overlays - Package modifications and custom packages
      # -------------------------------------------------------------------------
      overlays.default = import ./overlays/default.nix;

      # -------------------------------------------------------------------------
      # Packages - Installer images for different architectures
      # -------------------------------------------------------------------------
      packages = {
        # x86_64 packages - Build on x86_64 Linux (e.g., chestnut)
        x86_64-linux = {
          # Minimal installer ISO for regular PCs and servers
          # Build: nix build .#installer-iso
          installer-iso = nixos-generators.nixosGenerate {
            system = "x86_64-linux";
            modules = [ ./iso/default.nix ];
            format = "install-iso";
          };
        };

        # ARM64 packages - Build on aarch64 Linux (e.g., UTM VM)
        aarch64-linux = {
          # SD card image for Raspberry Pi 4/5
          # Build: nix build .#rpi-installer
          rpi-installer = nixos-generators.nixosGenerate {
            system = "aarch64-linux";
            modules = [ ./iso/default.nix ];
            format = "sd-aarch64-installer";
          };
        };
      };

      # =========================================================================
      # NixOS Configurations - Linux systems
      # =========================================================================
      nixosConfigurations = {

        # VM - Testing environment for NixOS
        # Build: nixos-rebuild build --flake .#vm
        # Switch: nixos-rebuild switch --flake .#vm
        vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/vm
            inputs.disko.nixosModules.disko
            home-manager.nixosModules.home-manager
            ./hosts/common/home-manager.nix
            { home-manager.users.nima = import ./home/nima/vm.nix; }
          ];
          specialArgs = { inherit inputs outputs; };
        };
        chestnut = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/chestnut
            # inputs.disko.nixosModules.disko  # Not needed for manual partitioning
            inputs.sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            ./hosts/common/home-manager.nix
            {
              home-manager.users.nima = import ./home/nima/chestnut.nix;
            }

            # Quadlet support for rootless Podman containers
            quadlet-nix.nixosModules.quadlet
            {
              # Home Manager for poddy user (minimal - just for Quadlet containers)
              home-manager.users.poddy = { pkgs, config, ... }: {
                imports = [ quadlet-nix.homeManagerModules.quadlet ];
                home.stateVersion = "25.05";
                # Quadlet container configuration is in hosts/common/podman/container-traefik.nix
              };
            }
          ];
          specialArgs = { inherit inputs outputs; };
        };
      };

      # =========================================================================
      # Darwin (macOS) Configurations
      # =========================================================================
      darwinConfigurations = {
        # Mac - Personal macOS system
        # Build: darwin-rebuild build --flake .#mac
        # Switch: darwin-rebuild switch --flake .#mac
        mac = darwin.lib.darwinSystem {
          system = "aarch64-darwin"; # Apple Silicon (M1/M2/M3)
          modules = [
            ./hosts/mac
            home-manager.darwinModules.home-manager
            ./hosts/common/home-manager.nix
            { home-manager.users.nima = import ./home/nima/mac.nix; }
          ];
          specialArgs = { inherit inputs outputs; };
        };
      };

      # =========================================================================
      # Colmena - Remote deployment configuration
      # Deploy: colmena apply
      # Deploy specific host: colmena apply --on chestnut
      # =========================================================================
      colmena = {
        meta = {
          nixpkgs = import nixpkgs { system = "x86_64-linux"; };
          specialArgs = { inherit inputs outputs; };
        };

        # Chestnut - Production server (a safe place for your "nuts"/data)
        # Address: chestnut.nmsd.xyz
        # Features: ZFS mirror pool, remote builds
        chestnut = {
          deployment = {
            targetHost = "chestnut.nmsd.xyz";
            targetUser = "root";
            buildOnTarget = true; # Build on server to avoid large transfers
            tags = [ "production" "storage" ];
          };

          imports = [
            ./hosts/chestnut
            # inputs.disko.nixosModules.disko  # Not needed for manual partitioning
            inputs.sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            ./hosts/common/home-manager.nix
            {
              home-manager.users.nima = import ./home/nima/chestnut.nix;
            }

            # Quadlet support for rootless Podman containers
            quadlet-nix.nixosModules.quadlet
            {
              # Home Manager for poddy user (minimal - just for Quadlet containers)
              home-manager.users.poddy = { pkgs, config, ... }: {
                imports = [ quadlet-nix.homeManagerModules.quadlet ];
                home.stateVersion = "25.05";
                # Quadlet container configuration is in hosts/common/podman/container-traefik.nix
              };
            }
          ];
        };
      };
    };
}
