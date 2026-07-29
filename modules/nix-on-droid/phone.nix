{
  config,
  inputs,
  ...
}:
{
  flake.nixOnDroidConfigurations.phone =
    inputs.nix-on-droid.lib.nixOnDroidConfiguration {
      pkgs = import inputs.android-nixpkgs {
        system = "aarch64-linux";
        overlays = [ inputs.nix-on-droid.overlays.default ];
      };

      home-manager-path = inputs.android-home-manager.outPath;

      modules = [
        inputs.self.nixOnDroidModules.base
        {
          home-manager = {
            backupFileExtension = "hm-bak";
            useGlobalPkgs = true;
            config = {
              imports = config.homeProfile.phone.modules;
              home.stateVersion = "24.05";
            };
          };
        }
      ];
    };
}
