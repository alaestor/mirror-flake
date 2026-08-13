{ inputs, self, ... }:
let
  hostFragments = import "${self}/hosts/noblesse";
in
{
  host.noblesse = rec {
    class = "nixOnDroid";
    description = "Android phone running nix-on-droid.";
    primaryUser = "nix-on-droid";
    stateVersion = "24.05";

    system = "aarch64-linux";
    nixpkgs = inputs.android-nixpkgs;

    # The device is too slow to realize its own bootstrap.
    nixOnDroid.bootstrapSystem = "x86_64-linux";

    # Nix-on-Droid pins its Home Manager to the Android nixpkgs release.
    homeManager.flake = inputs.android-home-manager;

    userEnvironment.${primaryUser} = {
      mode = "integrated";
      modules = [
        inputs.self.modules.homeManager.ssh-client
        { programs.home-manager.enable = true; }
      ]
      ++ hostFragments.homeManager;
    };

    modules = (with inputs.self.modules.nixOnDroid; [
      local-cache
      ssh-host
      tailnet-client
    ])
    ++ hostFragments.nixOnDroid;
  };
}
