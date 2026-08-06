{ inputs, lib, ... }:
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
        inputs.self.nixOnDroidModules.local-cache
        inputs.self.nixOnDroidModules.ssh-host
        inputs.self.nixOnDroidModules.tailscale
        (
          { config, pkgs, ... }:
          {
            environment.packages = with pkgs; [
              # NOTE(compatibility): complications around age sk decryption in nix-on-droid resulting from pcsc woes; see [age-plugin-yubikey#109](https://github.com/str4d/age-plugin-yubikey/issues/109)
              age
              age-plugin-yubikey
              doggo
              getent
            ];

            hostIdentity = {
              name = "noblesse";
              description = "Android phone running nix-on-droid.";
              primaryUser = "nix-on-droid";
              stateVersion = "24.05";
            };

            ssh-host = {
              comment = "generated host key (${config.hostIdentity.name})";
              allowUsers = [ config.hostIdentity.primaryUser ];
            };

            home-manager = {
              backupFileExtension = "hm-bak";
              useGlobalPkgs = true;
              config = {
                imports = [ inputs.self.modules.homeManager.phone ];
                home.stateVersion = config.hostIdentity.stateVersion;
                ssh-client.identityFiles = [ "~/.ssh/id_ed25519_${config.hostIdentity.name}" ];
              };
            };
          }
        )
      ];
    };
}
