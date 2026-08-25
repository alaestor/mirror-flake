{ config, lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot = {
    initrd.availableKernelModules = [
      "xhci_pci"
      "ahci"
      "nvme"
      "usbhid"
      "usb_storage"
      "sd_mod"
    ];
    kernelModules = [
      "kvm-amd"
      "xt_policy"
      "exfat"
      "nfsv4"
    ];
    loader.grub = {
      enable = true;
      device = "/dev/nvme0n1";
      useOSProber = true;
    };
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/ad2633a1-749c-4f66-92ee-76f622fa5672";
      fsType = "ext4";
    };
  };
  swapDevices = [
    { device = "/dev/disk/by-uuid/343255da-052c-4e75-88e5-381713edf427"; }
  ];

  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
