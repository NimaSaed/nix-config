# Nix Configuration Structure

This document describes the organization and structure of this Nix configuration.

## Overview

This is a multi-platform Nix configuration supporting:
- **NixOS** (VM and Server)
- **macOS** (via nix-darwin)
- **Home Manager** (cross-platform user environment)

## Directory Structure

```
nix-config/
├── flake.nix                      # Main flake configuration
├── flake.lock                     # Dependency lock file
│
├── hosts/                         # System configurations
│   ├── chestnut/                  # NAS/server configuration
│   │   ├── default.nix
│   │   ├── disko-nvme-boot-raid1.nix   # Boot disk layout
│   │   ├── disko-zfs-datapool.nix      # ZFS datapool layout
│   │   └── hardware-configuration.nix
│   │
│   ├── common/                    # Shared system modules
│   │   ├── core/                  # Shared system options
│   │   │   └── default.nix
│   │   ├── podman/                # Container infrastructure
│   │   │   └── podman.nix         # Podman configuration & auto-update
│   │   ├── users/                 # System user configurations
│   │   │   └── nima/              # Primary user configuration
│   │   └── home-manager.nix       # Host-side Home Manager setup
│   │
│   ├── mac/                       # macOS (nix-darwin) configuration
│   │   └── default.nix
│   │
│   └── vm/                        # NixOS VM configuration
│       ├── default.nix
│       ├── disko.nix              # Disk partitioning for the VM
│       └── hardware-configuration.nix
│
├── home/                          # Home Manager configurations
│   └── nima/
│       ├── common/
│       │   └── core/              # Shared user environment modules
│       │       ├── bash.nix
│       │       ├── bat.nix
│       │       ├── default.nix
│       │       ├── direnv.nix
│       │       ├── eza.nix
│       │       ├── git.nix
│       │       ├── packages.nix
│       │       ├── tmux.nix
│       │       └── zoxide.nix
│       │
│       ├── chestnut.nix           # Host-specific home config
│       ├── mac.nix                # macOS-specific home config
│       ├── ssh.pub                # Public SSH key for deployments
│       └── vm.nix                 # VM-specific home config
│
├── iso/                           # NixOS installer images
│   └── default.nix                # ISO build configuration
│
├── overlays/                      # Package overlays
│   └── default.nix                # Custom package modifications
│
└── scripts/                       # Helper scripts
    ├── authorize-key.sh
    ├── disko.sh
    ├── install.sh
    └── update.sh
```

## Usage

### NixOS Systems

**VM (Testing):**
```bash
nixos-rebuild build --flake .#vm
nixos-rebuild switch --flake .#vm
```

**Server (via Colmena):**
```bash
colmena apply                    # Deploy all hosts
colmena apply --on server        # Deploy only server
```

### macOS System

```bash
darwin-rebuild build --flake .#mac
darwin-rebuild switch --flake .#mac
```

### Build Custom Installer ISO

```bash
# Build bootable installer image
nix build .#installer-iso

# ISO will be in result/iso/
ls -lh result/iso/*.iso
```

### Format Nix Files

```bash
nix fmt
```

### Update Dependencies

```bash
nix flake update
```

## Container Infrastructure

This configuration includes Podman for containerized workloads with the following features:

- **Rootless Podman**: Secure container runtime with Docker compatibility
- **Auto-Update**: Automated daily updates for containers with `io.containers.autoupdate=registry` label
- **Auto-Prune**: Weekly cleanup of unused images and containers
- **DNS Enabled**: Proper DNS resolution for rootless containers

The Podman configuration is located at `hosts/common/podman/podman.nix` and can be imported by any host.

## ISO Building

Build custom NixOS installer images for deployment:

```bash
# Build x86_64 installer ISO
nix build .#installer-iso

# Find the generated ISO
ls -lh result/iso/*.iso
```

The ISO configuration is in `iso/default.nix` and creates bootable installer images with your SSH keys and configuration pre-loaded for automated deployments with `nixos-anywhere`.

## Configuration Hierarchy

### System Level (hosts/)
- Hardware configuration
- System packages
- Services and daemons
- User account definitions
- ZFS/disk configuration
- Container infrastructure (Podman)

### User Level (home/)
- User packages
- Dotfiles and application configs
- Shell configuration
- Development tools

### Shared Configurations
- `hosts/common/core/`: System-wide packages (vim, git)
- `hosts/common/podman/`: Container infrastructure modules
- `hosts/common/users/`: System user configurations
- `hosts/common/home-manager.nix`: Shared Home Manager wiring for hosts
- `home/nima/common/core/`: User environment essentials

## Adding New Configurations

### Add a New Host

1. Create `hosts/newhostname/default.nix`
2. Add to `flake.nix`:
```nix
nixosConfigurations.newhostname = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    ./hosts/newhostname
    # ... other modules
  ];
};
```

### Add a New Application Module

1. Create `home/nima/common/core/appname.nix`
2. Import in `home/nima/common/core/default.nix`:
```nix
imports = [
  ./appname.nix
  # ... other modules
];
```

### Add a Package Overlay

Edit `overlays/default.nix`:
```nix
final: prev: {
  myPackage = prev.myPackage.overrideAttrs (old: {
    version = "1.2.3";
  });
}
```

## Useful Commands

```bash
# Show flake info
nix flake show

# Check flake
nix flake check

# Update specific input
nix flake lock --update-input nixpkgs

# List generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Rollback
sudo nixos-rebuild switch --rollback
```
