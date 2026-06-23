{
  /**
    Creates a minimal NixOS installer ISO file no grub countdown or `wpa_supplicant`.

    Use `networking.wireless.enable = lib.mkForce true;` if you want to re-enable `wpa_supplicant`
  */
  flake.modules.nixos.isolive = { modulesPath, lib, ... } : let
    # one stronger than mkImageMediaOverride (60), but weaker than mkForce (50)
    # https://github.com/NixOS/nixpkgs/blob/a54c095498f6f74fbd4f91f709b351d958e2ab08/lib/modules.nix#L1550
    mkLessForce = lib.mkOverride 55;
    # use the same value as installation-cd-minimal.nix
    mkMoreDefault = lib.mkOverride 500;
  in{
    imports = [
      #(modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
      (modulesPath + "/profiles/minimal.nix")
      (modulesPath + "/installer/cd-dvd/installation-cd-base.nix")
      ({
        documentation.man.enable      = mkMoreDefault false;
        documentation.doc.enable      = mkMoreDefault false;
        fonts.fontconfig.enable       = mkMoreDefault false;
        isoImage.edition              = mkMoreDefault "minimal";
        isoImage.forceTextMode        = mkMoreDefault true;
        isoImage.grubTheme            = mkLessForce null;
        #isoImage.squashfsCompression  = "zstd"; # uncomment for faster build (larger image)
        # Boot immediately — no 10s GRUB countdown on live sessions
        boot.loader.timeout           = mkLessForce 0;
        # disable wpa_supplicant added by installation-cd-minimal.nix
        networking.wireless.enable    = mkLessForce false;
      })
    ];
  };
}
