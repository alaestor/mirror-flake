{
  /**
    Creates a minimal NixOS installer ISO file no grub countdown, optimized for image size.
  */
  flake.modules.nixos.isolive-minimal = { modulesPath, lib, pkgs, ... } : let
    # one stronger than mkImageMediaOverride (60), but weaker than mkForce (50)
    # https://github.com/NixOS/nixpkgs/blob/a54c095498f6f74fbd4f91f709b351d958e2ab08/lib/modules.nix#L1550
    mkLessForce = lib.mkOverride 55;
    # use the same value as installation-cd-minimal.nix
    mkMoreDefault = lib.mkOverride 500;
  in{
    imports = [
      (modulesPath + "/profiles/minimal.nix")
      (modulesPath + "/installer/cd-dvd/installation-cd-base.nix")
      ({
        isoImage.edition                        = mkMoreDefault "minimal";
        isoImage.forceTextMode                  = mkMoreDefault true;
        isoImage.grubTheme                      = mkLessForce null;
        #isoImage.squashfsCompression            = "zstd"; # uncomment for faster build (larger image)
        # Boot immediately — no 10s GRUB countdown on live sessions
        boot.loader.timeout                     = mkLessForce 0;
        # Drop non-free/redistributable firmware (Wi-Fi blobs, GPU blobs, etc.)
        hardware.enableRedistributableFirmware  = mkLessForce false;
        # Drop documentation (man pages, NixOS manual HTML, info pages)
        documentation.enable                    = mkLessForce false;
        documentation.man.enable                = mkLessForce false;
        documentation.nixos.enable              = mkLessForce false;
        documentation.doc.enable                = mkLessForce false;
        documentation.info.enable               = mkLessForce false;
        # Drop wireless (saves wpa_supplicant, iwd, etc.)
        networking.wireless.enable              = mkLessForce false;
        # Drop fontconfig + default fonts (installer is console-only)
        fonts.fontconfig.enable                 = mkLessForce false;
        fonts.enableDefaultPackages             = mkLessForce false;
        # Drop speech synthesis
        services.speechd.enable                 = mkLessForce false;
        # Drop graphics acceleration (no GPU needed for installer)
        hardware.graphics.enable                = mkLessForce false;
        # Drop sound/input services
        services.pipewire.enable                = mkLessForce false;
        services.libinput.enable                = mkLessForce false;
        # Restrict initrd kernel modules to what you actually need
        #boot.initrd.availableKernelModules      = [ "ahci" "xhci_pci" "usb_storage" "virtio_pci" "virtio_blk" "ext4" "btrfs" "xfs" ];
        # Restrict supported filesystems (only what disko will use)
        #boot.supportedFilesystems               = [ "ext4" "btrfs" "xfs" "vfat" ];
        # Drop extraDependencies (stdenv) — speeds up build but means more downloads at install time
        system.extraDependencies                = mkLessForce [];
      })
    ];
  };
}
