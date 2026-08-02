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
          { config, pkgs, ... }:
          {
            environment.packages = with pkgs; [
              # NOTE(compatibility): complications around age sk decryption in nix-on-droid resulting from pcsc woes; see [age-plugin-yubikey#109](https://github.com/str4d/age-plugin-yubikey/issues/109)
              age
              age-plugin-yubikey
            ];

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

                home.file.".config/age/recipients/administrative".source =
                  inputs.self.data.path "identities/administrative/age_primary";
              };
            };
          }
        )
      ];
    };
}
