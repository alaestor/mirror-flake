{ inputs, config, lib, ... }:
let
  phoneProfile = config.homeProfile.phone.modules;
in
{
  options.flake.nixOnDroidConfigurations = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = "Nix-on-Droid configurations exported by this flake.";
  };

  /**
    Cross compiling
      pc -> nix build --no-link --print-out-paths .#nixOnDroidConfigurations.ts.activationPackage
      copy path
      droid -> nix copy --from ssh-ng://user@172.16.0.8?ssh-key=.ssh/id_ed25519_noblesse <nix/store/
  */

  config = {
    flake-file.inputs.nix-on-droid-ts = {
      url = "github:alaestor/fork-nix-on-droid/better-cross-compile-1";
      inputs.nixpkgs.follows = "android-nixpkgs";
      inputs.home-manager.follows = "android-home-manager";
    };

    flake.nixOnDroidConfigurations.ts =
      inputs.nix-on-droid-ts.lib.nixOnDroidConfiguration
        {
          pkgs = import inputs.android-nixpkgs {
            system = "aarch64-linux";
            overlays = [ inputs.nix-on-droid-ts.overlays.default ];
          };

          home-manager-path = inputs.android-home-manager.outPath;

          bootstrapSystem = "x86_64-linux";

          modules = [
            inputs.self.nixOnDroidModules.base
            inputs.self.nixOnDroidModules.host-identity
            inputs.self.nixOnDroidModules.local-cache
            inputs.self.nixOnDroidModules.ssh-host
            ({ config, pkgs, ... }:
            {
              system.stateVersion = "24.05";

              user = {
                uid = 10229;
                gid = 10229;
              };

              environment.etc."resolv.conf".text = lib.mkForce ''
                nameserver 100.100.100.100
              '';

              ssh-host = {
                comment = "generated host key (${config.hostIdentity.name})";
                allowUsers = [ config.hostIdentity.primaryUser ];
              };

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

              home-manager = {
                backupFileExtension = "hm-bak";
                useGlobalPkgs = true;
                config = {
                  imports = phoneProfile;
                  home.stateVersion = config.hostIdentity.stateVersion;
                  home.shellAliases.nswitch =
                    "nix-on-droid switch --flake git+https://codeberg.org/alaestor/flake#noblesse";
                  ssh-client.identityFiles = [ "~/.ssh/id_ed25519_${config.hostIdentity.name}" ];
                };
              };
            })
          ];
        };
  };
}
