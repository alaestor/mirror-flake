{ inputs, lib, ... }:
{
  options.flake.nixOnDroidConfigurations = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = "Nix-on-Droid configurations exported by this flake.";
  };

  config = {
    flake.nixOnDroidConfigurations.noblesse =
      inputs.nix-on-droid.lib.nixOnDroidConfiguration
        {
          pkgs = import inputs.android-nixpkgs {
            system = "aarch64-linux";
            overlays = [ inputs.nix-on-droid.overlays.default ];
          };

          home-manager-path = inputs.android-home-manager.outPath;

          bootstrapSystem = "x86_64-linux";

          modules = (with inputs.self.nixOnDroidModules; [
            base
            host-identity
            local-cache
            ssh-host
            tailnet-client
          ]) ++ [
            ({ config, pkgs, ... }:
            {

              user = {
                uid = 10229;
                gid = 10229;
              };

              ssh-host = {
                comment = "generated host key (${config.hostIdentity.name})";
                allowUsers = [ config.hostIdentity.primaryUser ];
              };

              environment.packages = with pkgs; [
                openssh
                # NOTE(compatibility): complications around age sk decryption in nix-on-droid resulting from pcsc woes; see [age-plugin-yubikey#109](https://github.com/str4d/age-plugin-yubikey/issues/109)
                age
                age-plugin-yubikey
                doggo
                curl
                ripgrep
              ];

              nix.extraOptions = lib.mkAfter ''
                builders = ssh://user@apc.tailnet.0x04.cc aarch64-linux,x86_64-linux /data/data/com.termux.nix/files/home/.ssh/id_ed25519_noblesse 8 10
                builders-use-substitutes = true
              '';

              # TODO(droid): can these be generalized in base?
              environment.sessionVariables.HOSTNAME = config.hostIdentity.name;
              system.stateVersion = config.hostIdentity.stateVersion;
              #user.userName = config.hostIdentity.primaryUser; # TODO(droid): experiment; if we set droid name to `user` it may conflict with existing ownership

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
                  imports = [ inputs.self.modules.homeManager.phone ];
                  home.stateVersion = config.hostIdentity.stateVersion;
                  ssh-client.identityFiles = [ "~/.ssh/id_ed25519_${config.hostIdentity.name}" ];
                };
              };

            })
          ];
        };
  };
}
