# Plan: Create nutcracker host boilerplate

## Summary
Create a new NixOS host called "nutcracker" following the same patterns as chestnut. This will be a x86_64 VM with a single disk layout and Colmena deployment support.

## Best Practices Applied (from Context7)
- **Disko**: Use modern GPT type with `priority` field for partition ordering
- **Disko**: BIOS boot partition uses type "EF02" (correct for GRUB + GPT)
- **sops-nix**: Use `sops.age.generateKey = true` to auto-generate key on first boot
- **sops-nix**: Use `validateSopsFiles = true` to validate at evaluation time

## Files to Create

### 1. `hosts/nutcracker/default.nix`
Main host configuration with:
- Imports: disko.nix, hardware-configuration.nix, common/core, common/users/nima
- GRUB bootloader (same as chestnut)
- zramSwap enabled
- Networking: hostName = "nutcracker", networkmanager enabled
- systemd network-online.target fix (for future podman)
- Localization (same timezone/locale as chestnut)
- OpenSSH enabled
- Root user with SSH keys
- SOPS configuration with `age.generateKey = true` for auto key generation
- **No podman services enabled** (commented placeholder for future)
- stateVersion = "25.05"

### 2. `hosts/nutcracker/disko.nix`
Single disk configuration (following modern disko patterns):
- `/dev/sda` with GPT partitioning
- 1M BIOS boot partition (type "EF02", priority 1)
- XFS root filesystem (size "100%", priority 2)

### 3. `hosts/nutcracker/hardware-configuration.nix`
QEMU guest profile (same as chestnut):
- Import qemu-guest.nix profile
- Kernel modules: ata_piix, uhci_hcd, virtio_pci, virtio_scsi, sd_mod, sr_mod
- x86_64-linux platform

### 4. `hosts/nutcracker/secrets.yaml`
Minimal SOPS-encrypted secrets file. Must be initialized with:
```bash
# After adding nutcracker's age public key to .sops.yaml
sops hosts/nutcracker/secrets.yaml
```
Will create with empty placeholder structure for now.

### 5. `home/nima/nutcracker.nix`
Home-manager configuration:
- Import common/core
- Basic home settings (username, homeDirectory, stateVersion)
- Minimal packages (tmux, screen)
- Same structure as chestnut.nix

## Files to Modify

### 6. `flake.nix`
Add nutcracker integration:
- Create `nutcrackerModules` list (similar to chestnutModules but without ./modules/podman)
- Add `nixosConfigurations.nutcracker` entry
- Add `colmena.nutcracker` deployment config targeting nutcracker.nmsd.xyz

### 7. `.sops.yaml`
Add nutcracker secrets configuration:
- Add placeholder key entry for nutcracker (will update with real age key after first boot)
- Add creation_rule for `hosts/nutcracker/secrets\.yaml$` path

## Secrets Workflow (post-implementation)
After nutcracker is deployed:
1. Get age public key from nutcracker: `ssh nutcracker "cat /var/lib/sops-nix/key.txt | age-keygen -y"`
2. Update `.sops.yaml` with the real nutcracker age key
3. Run `sops hosts/nutcracker/secrets.yaml` to initialize encrypted secrets

## Verification

1. Run `nix flake check` to validate syntax
2. Run `nix build .#nixosConfigurations.nutcracker.config.system.build.toplevel` to test build
3. (Future) Deploy with `colmena apply --on nutcracker` once VM is set up
