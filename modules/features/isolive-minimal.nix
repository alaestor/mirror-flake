{ inputs, ... }:
{
  /**
    Creates a minimal NixOS installer ISO file no grub countdown, optimized for image size. Builds on `isolive`, trimming further: no firmware blobs, wireless, documentation, fonts, speech synthesis, graphics acceleration, or sound/input services.
  */
  flake.modules.nixos.isolive-minimal =
    { lib, ... }:
    let
      # one stronger than mkImageMediaOverride (60), but weaker than mkForce (50)
      # https://github.com/NixOS/nixpkgs/blob/a54c095498f6f74fbd4f91f709b351d958e2ab08/lib/modules.nix#L1550
      mkLessForce = lib.mkOverride 55;
    in
    {
      imports = [
        inputs.self.modules.nixos.isolive
        ({
          # Drop non-free/redistributable firmware (Wi-Fi blobs, GPU blobs, etc.)
          hardware.enableRedistributableFirmware = mkLessForce false;
          # Drop documentation (man pages, NixOS manual HTML, info pages)
          documentation.enable = mkLessForce false;
          documentation.nixos.enable = mkLessForce false;
          documentation.info.enable = mkLessForce false;
          # Drop fonts + default font packages (installer is console-only)
          fonts.enableDefaultPackages = mkLessForce false;
          # Drop speech synthesis
          services.speechd.enable = mkLessForce false;
          # Drop graphics acceleration (no GPU needed for installer)
          hardware.graphics.enable = mkLessForce false;
          # Drop sound/input services
          services.pipewire.enable = mkLessForce false;
          services.libinput.enable = mkLessForce false;
          # Restrict initrd kernel modules to what you actually need
          #boot.initrd.availableKernelModules      = [ "ahci" "xhci_pci" "usb_storage" "virtio_pci" "virtio_blk" "ext4" "btrfs" "xfs" ];
          # Restrict supported filesystems (only what disko will use)
          #boot.supportedFilesystems               = [ "ext4" "btrfs" "xfs" "vfat" ];
          # Drop extraDependencies (stdenv) — speeds up build but means more downloads at install time
          system.extraDependencies = mkLessForce [ ];
        })
      ];
    };
}
