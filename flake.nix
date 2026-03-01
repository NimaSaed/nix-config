{
  description = "Nima's Personal Nix Configuration";

  # ============================================================================
  # Flake Inputs - External dependencies and their sources
  # ============================================================================
  inputs = {
    # Nixpkgs - The main package repository (stable 25.11 branch)
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    # Nixpkgs Unstable
    # Access via pkgs.unstable.<package>
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # Home Manager - Declarative user environment management
    # Follows nixpkgs version to ensure compatibility
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # nix-darwin - macOS system configuration management (stable 25.11)
    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
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
    quadlet-nix = {
      url = "github:SEIAROTg/quadlet-nix";
    };

    # nix-homebrew - Declarative Homebrew management for macOS
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  };

  # ============================================================================
  # Flake Outputs - What this flake provides
  # ============================================================================
  outputs =
    {
      self,
      disko,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      darwin,
      nixos-generators,
      sops-nix,
      quadlet-nix,
      nix-homebrew,
      ...
    }@inputs:
    let
      inherit (self) outputs;

      # Shared overlay module applied to all hosts.
      # Includes custom package overrides and unstable channel access.
      sharedOverlayModule =
        { pkgs, ... }:
        {
          nixpkgs.overlays = [
            outputs.overlays.default
            (final: prev: {
              unstable = import nixpkgs-unstable {
                system = prev.system;
                config.allowUnfree = true;
              };
            })
          ];
        };

      # Shared modules for chestnut host - used by both nixosConfigurations and colmena
      chestnutModules = [
        sharedOverlayModule
        ./hosts/chestnut
        inputs.disko.nixosModules.disko
        inputs.sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        ./hosts/common/home-manager.nix
        { home-manager.users.nima = import ./home/nima/chestnut.nix; }
        ./modules/podman
      ];

      # Shared modules for nutcracker host - used by both nixosConfigurations and colmena
      nutcrackerModules = [
        sharedOverlayModule
        ./hosts/nutcracker
        inputs.disko.nixosModules.disko
        inputs.sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        ./hosts/common/home-manager.nix
        { home-manager.users.nima = import ./home/nima/nutcracker.nix; }
        ./modules/podman
      ];

      # Modules for hazelnut host - LattePanda iota desktop/workstation
      hazelnutModules = [
        sharedOverlayModule
        ./hosts/hazelnut
        inputs.disko.nixosModules.disko
        inputs.sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        ./hosts/common/home-manager.nix
        { home-manager.users.nima = import ./home/nima/hazelnut.nix; }
      ];

      # Modules for walnut host - VPS WireGuard relay (minimal, no home-manager/podman)
      walnutModules = [
        sharedOverlayModule
        ./hosts/walnut
        inputs.disko.nixosModules.disko
        inputs.sops-nix.nixosModules.sops
      ];

    in
    {
      # -------------------------------------------------------------------------
      # Formatter - Format Nix files with `nix fmt`
      # -------------------------------------------------------------------------
      formatter = {
        x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt;
        aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt;
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
            sharedOverlayModule
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
          modules = chestnutModules;
          specialArgs = { inherit inputs outputs; };
        };

        # Nutcracker - Service runner (processes data from chestnut)
        # Build: nixos-rebuild build --flake .#nutcracker
        # Switch: nixos-rebuild switch --flake .#nutcracker
        nutcracker = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = nutcrackerModules;
          specialArgs = { inherit inputs outputs; };
        };

        # Hazelnut - Desktop/workstation (LattePanda iota)
        # Build: nixos-rebuild build --flake .#hazelnut
        # Switch: nixos-rebuild switch --flake .#hazelnut --target-host root@hazelnut.local
        hazelnut = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = hazelnutModules;
          specialArgs = { inherit inputs outputs; };
        };

        # Walnut - VPS relay (WireGuard tunnel + NAT port forwarding)
        # Hides chestnut's home IP; forwards ports 80/443 to chestnut via WireGuard
        walnut = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = walnutModules;
          specialArgs = { inherit inputs outputs; };
        };

        # Walnut VM - local test build for Apple Silicon Mac
        # Build: nix build .#nixosConfigurations.walnut-vm.config.system.build.vm
        # Run:   ./result/bin/run-walnut-vm-vm
        walnut-vm = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = walnutModules ++ [
            {
              nixpkgs.hostPlatform = nixpkgs.lib.mkForce "aarch64-linux";

              users.users.root.initialHashedPassword = "";
              services.getty.autologinUser = "root";

              networking.nat.externalInterface = nixpkgs.lib.mkForce "eth0";

              virtualisation.vmVariant.virtualisation = {
                memorySize = 512;
                cores = 1;
                host.pkgs = nixpkgs.legacyPackages.aarch64-darwin;
                forwardPorts = [
                  { from = "host"; host.port = 8080; guest.port = 80;    }
                  { from = "host"; host.port = 8443; guest.port = 443;   }
                  { from = "host"; host.port = 51820; guest.port = 51820; proto = "udp"; }
                ];
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
            sharedOverlayModule
            ./hosts/mac
            home-manager.darwinModules.home-manager
            ./hosts/common/home-manager.nix
            {
              home-manager.users.nima = import ./home/nima/mac.nix;
            }
            # Homebrew management
            nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                enable = true;
                enableRosetta = true; # Apple Silicon Rosetta support
                user = "nima";
                autoMigrate = true;
              };
            }
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
          nixpkgs = nixpkgs.legacyPackages.x86_64-linux;
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
            tags = [
              "production"
              "storage"
            ];
          };
          imports = chestnutModules;
        };

        # Nutcracker - Service runner (processes data from chestnut)
        # Address: nutcracker.nmsd.xyz
        # Features: Podman services (future migration from chestnut)
        nutcracker = {
          deployment = {
            targetHost = "nutcracker.nmsd.xyz";
            targetUser = "root";
            buildOnTarget = true; # Build on server to avoid large transfers
            tags = [
              "production"
              "services"
            ];
          };
          imports = nutcrackerModules;
        };

        # Walnut - VPS WireGuard relay
        # Deploy: colmena apply --on walnut
        walnut = {
          deployment = {
            targetHost = "walnut.nmsd.xyz";
            targetUser = "root";
            buildOnTarget = true;
            tags = [ "walnut" ];
          };
          imports = walnutModules;
        };
      };
    };
}
