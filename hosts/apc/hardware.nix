{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot = {
    binfmt.emulatedSystems = [ "aarch64-linux" ]; # to cross-compile for noblesse
    kernelPackages = pkgs.linuxPackages_latest;
    initrd = {
      availableKernelModules = [
        "nvme"
        "xhci_pci"
        "ahci"
        "usb_storage"
        "usbhid"
        "sd_mod"
      ];
      luks.devices = {
        "luks-98abcfc9-20d2-4af9-ac5f-09c72359086e".device =
          "/dev/disk/by-uuid/98abcfc9-20d2-4af9-ac5f-09c72359086e";
        "luks-9fd45c42-514d-47e6-975c-88e6e8bafec3".device =
          "/dev/disk/by-uuid/9fd45c42-514d-47e6-975c-88e6e8bafec3";
      };
    };
    kernelModules = [
      "amdgpu"
      "kvm-amd"
      "nfsv4"
      "exfat"
      "ntfs3"
      "rpcsec_gss_krb5"
      "qrtr"
      "snd_hrtimer"
      "snd_seq"
      "snd_seq_dummy"
      "xt_policy"
    ];
    # Baseline slab_nomerge/page_poison/kernel.sysctl/blacklistedKernelModules
    # hardening comes from the `server-hardening` feature module
    # (`modules/features/server-hardening.nix`), which this host imports.
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/b8d36e54-a050-4606-b99b-b169a732c561";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/D817-CBDF";
      fsType = "vfat";
      options = [
        "fmask=0022"
        "dmask=0022"
      ];
    };
  };

  hardware = {
    cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = [ pkgs.rocmPackages.clr.icd ];
    };
    gpgSmartcards.enable = true;
  };

  # TODO(apc): legacy rocm hip rule; still needed?
  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
  ];
}
