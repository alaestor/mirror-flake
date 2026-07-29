{
  config,
  inputs,
  ...
}:
let
  phoneProfile = config.homeProfile.phone.modules;
in
{
  flake.nixOnDroidConfigurations.noblesse =
    inputs.nix-on-droid.lib.nixOnDroidConfiguration {
      pkgs = import inputs.android-nixpkgs {
        system = "aarch64-linux";
        overlays = [ inputs.nix-on-droid.overlays.default ];
      };

      home-manager-path = inputs.android-home-manager.outPath;

      modules = [
        inputs.self.nixOnDroidModules.base
        inputs.self.nixOnDroidModules.host-identity
        (
          { config, ... }:
          {
            hostIdentity = {
              name = "noblesse";
              description = "Android phone running nix-on-droid.";
              primaryUser = "nix-on-droid";
              stateVersion = "24.05";
            };

            home-manager = {
              backupFileExtension = "hm-bak";
              useGlobalPkgs = true;
              config = {
                imports = phoneProfile;
                home.stateVersion = config.hostIdentity.stateVersion;
              };
            };
          }
        )
      ];
    };
}
