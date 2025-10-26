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
├── flake.nix                    # Main flake configuration
├── flake.lock                   # Dependency lock file
│
├── hosts/                       # System configurations
│   ├── common/                  # Shared system modules
│   │   ├── core/               # Core packages (vim, git)
│   │   ├── optional/           # Optional modules
│   │   ├── users/              # User account definitions
│   │   └── home-manager.nix    # Shared home-manager settings
│   │
│   ├── mac/                    # macOS configuration
│   │   └── default.nix
│   │
│   ├── vm/                     # VM configuration
│   │   ├── default.nix
│   │   ├── disko.nix          # Disk partitioning
│   │   └── hardware-configuration.nix
│   │
│   └── server/                 # Server configuration
│       ├── default.nix
│       ├── disko.nix          # ZFS mirror setup
│       └── hardware-configuration.nix
│
├── home/                       # Home Manager configurations
│   └── nima/
│       ├── common/            # Shared home configurations
│       │   └── core/          # Core apps and settings
│       │       ├── default.nix      # Module aggregator
│       │       ├── git.nix          # Git configuration
│       │       ├── bash.nix         # Bash configuration
│       │       ├── direnv.nix       # Direnv configuration
│       │       ├── starship.nix     # Starship prompt
│       │       ├── bat.nix          # Bat (better cat)
│       │       ├── eza.nix          # Eza (better ls)
│       │       ├── zoxide.nix       # Zoxide (smart cd)
│       │       └── packages.nix     # Common packages
│       │
│       ├── mac.nix            # macOS-specific home config
│       ├── vm.nix             # VM-specific home config
│       └── server.nix         # Server-specific home config
│
└── overlays/                   # Package overlays
    └── default.nix            # Custom package modifications
```

## Key Improvements

### 1. **Modular Home Manager Configuration**
- Created separate files for each application (`git.nix`, `bash.nix`, etc.)
- Easy to enable/disable specific tools
- Shared configurations across all machines via `common/core/`

### 2. **Darwin (macOS) Support**
- Added nix-darwin input and configuration
- Configured system defaults (dock, finder, keyboard)
- Ready to use with `darwin-rebuild switch --flake .#mac`

### 3. **Eliminated Duplication**
- Created `hosts/common/home-manager.nix` shared module
- Removed repeated home-manager configuration blocks
- Consistent settings across all hosts

### 4. **Standard Flake Outputs**
- **formatter**: Format Nix files with `nix fmt`
- **nixosModules**: Reusable modules for other flakes
- **overlays**: Package modifications and custom packages

### 5. **Better Documentation**
- Comprehensive comments in `flake.nix`
- Usage examples for each configuration
- Clear structure and organization

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

### Format Nix Files

```bash
nix fmt
```

### Update Dependencies

```bash
nix flake update
```

## Configuration Hierarchy

### System Level (hosts/)
- Hardware configuration
- System packages
- Services and daemons
- User account definitions
- ZFS/disk configuration

### User Level (home/)
- User packages
- Dotfiles and application configs
- Shell configuration
- Development tools

### Shared Configurations
- `hosts/common/core/`: System-wide packages (vim, git)
- `hosts/common/users/`: User account definitions
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

## Best Practices

1. **Keep modules focused**: Each file should configure one application
2. **Use shared modules**: Avoid duplication across hosts
3. **Document changes**: Add comments for non-obvious configurations
4. **Test changes**: Use VM configuration for testing before deploying
5. **Pin versions**: Use `flake.lock` for reproducibility

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

## Next Steps

- [ ] Update git username/email in `home/nima/common/core/git.nix`
- [ ] Customize starship prompt in `home/nima/common/core/starship.nix`
- [ ] Add machine-specific packages to respective `home/nima/{mac,vm,server}.nix`
- [ ] Configure Homebrew packages for macOS (optional)
- [ ] Add optional modules for specific use cases
