{ lib, ... }:
{
  options.flake.nixOnDroidModules = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.deferredModule;
    default = { };
    description = "Reusable nix-on-droid modules exported by this flake.";
  };

  config.flake.nixOnDroidModules.base =
    { pkgs, ... }:
    {
      environment = {
        etcBackupExtension = ".bak";
        packages = with pkgs; [
          git
          neovim
          openssh
          ripgrep
        ];
      };

      nix.extraOptions = ''
        experimental-features = nix-command flakes
      '';

      nix.nixPath = [ "nixpkgs=${pkgs.path}" ]; # TODO(workaround): nix-on-droid flakes dont expose nixpkgs in NIX_PATH; see [nix-on-droid#499](https://github.com/nix-community/nix-on-droid/issues/499)
    };
}
