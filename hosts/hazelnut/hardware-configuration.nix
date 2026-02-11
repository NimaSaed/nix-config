# Hardware configuration for hazelnut (LattePanda iota)
# Board: SBCADLCXR120-16G-B
# CPU: Intel N150 (Alder Lake-N), 16GB LPDDR5, 128GB eMMC 5.1
# GPU: Intel Alder Lake-N [8086:46d4] (i915)
# WiFi: Intel Wi-Fi 7 BE200 (iwlwifi)
# Audio: Intel HDA PCH + Realtek codec, Intel SOF
# Co-processor: RP2040 MCU (USB serial, cdc_acm)
# Touchscreen: Goodix GDIX1001 (I2C, goodix_ts)
# TPM: 2.0 (tpm_crb)
{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "usbhid"
    "uas"
    "sd_mod"
    "sdhci_pci"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # Filesystem mounts are handled by disko.nix

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Enable redistributable firmware for:
  # - Intel Wi-Fi 7 BE200 (iwlwifi)
  # - Intel GPU GuC/HuC (i915)
  # - Intel SOF audio firmware
  # - Intel CPU microcode
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
