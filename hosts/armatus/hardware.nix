{ config, lib, ... }:
{
  # TODO(armatus): consider systemd-boot.enable = true;efi.canTouchEfiVariables = true;
  boot = {
    supportedFilesystems.btrfs = true;
    kernelModules = [ "kvm-intel" ];
    initrd.availableKernelModules = [ "e1000e" ];
    loader.grub = {
      efiSupport = true;
      efiInstallAsRemovable = true;
      device = "nodev";
    };
  };

  services.xserver.videoDrivers = [ "nvidia" ];
  hardware = {
    cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      open = false; # Pascal requires the proprietary kernel module
      package = config.boot.kernelPackages.nvidiaPackages.legacy_580; # P5000
      prime = {
        offload = {
          enable = true;
          enableOffloadCmd = true;
        };
        intelBusId = "PCI:0:2:0";
        nvidiaBusId = "PCI:1:0:0";
      };
    };
  };
}
