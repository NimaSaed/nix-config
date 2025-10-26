{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Hardware detection - kernel modules for this system
  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "usbhid" "uas" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # Filesystems are managed by disko configurations:
  # - disko-nvme-boot-raid1.nix (boot partition with RAID1)
  # - disko-zfs-datapool.nix (ZFS data pool)

  # Network configuration
  networking.useDHCP = lib.mkDefault true;

  # Platform and hardware
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Enable software RAID support
  boot.swraid.enable = true;
}
