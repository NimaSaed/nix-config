{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "usbhid" "uas" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  #fileSystems."/" =
  #  { device = "/dev/disk/by-uuid/e664545d-9ee4-4e4a-a8cd-dfb9c9ba49c9";
  #    fsType = "btrfs";
  #    options = [ "subvol=rootfs" ];
  #  };

  #fileSystems."/boot" =
  #  { device = "/dev/disk/by-uuid/811E-7A22";
  #    fsType = "vfat";
  #    options = [ "fmask=0077" "dmask=0077" ];
  #  };

  #fileSystems."/home" =
  #  { device = "/dev/disk/by-uuid/e664545d-9ee4-4e4a-a8cd-dfb9c9ba49c9";
  #    fsType = "btrfs";
  #    options = [ "subvol=home" ];
  #  };

  #fileSystems."/nix" =
  #  { device = "/dev/disk/by-uuid/e664545d-9ee4-4e4a-a8cd-dfb9c9ba49c9";
  #    fsType = "btrfs";
  #    options = [ "subvol=nix" ];
  #  };

  #swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  boot.swraid.enable = true;


}
