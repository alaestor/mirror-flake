{
  inputs,
  lib,
  ...
}:
{

  options.flake.lib = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
  };

  config.flake.lib = let
    #global-nixos-settings = {
    #  nixpkgs.config.allowUnfree = true;
    #};
  in
  {
    /**
      #### Helper functions for creating system / home-manager configurations
      - mkNixos system name nixpkgs;
      - mkDarwin system name nixpkgs nix-darwin;
      - mkHomeManager system name nixpkgs home-manager;

      E.g.
      ```
      flake.nixosConfigurations = inputs.self.lib.mkNixos
        "x86_64-linux" "desktop" inputs.unstable-nixpkgs;
      ```
    */
    mkNixos = system: name: nixpkgs: {
      ${name} = nixpkgs.lib.nixosSystem {
        modules = [
          inputs.self.modules.nixos.${name}
          inputs.self.modules.nixos.global-config
          { nixpkgs.hostPlatform = lib.mkDefault system; }
        ];
      };
    };

    mkDarwin = system: name: nixpkgs: nix-darwin: {
      ${name} = nix-darwin.lib.darwinSystem {
        modules = [
          inputs.self.modules.darwin.${name}
          inputs.self.modules.nixos.global-config
          { nixpkgs.hostPlatform = lib.mkDefault system; }
        ];
      };
    };

    mkHomeManager = system: name: nixpkgs: home-manager: {
      ${name} = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        modules = [
          inputs.self.modules.homeManager.${name}
          inputs.self.modules.nixos.global-config
        ];
      };
    };

  };
}
