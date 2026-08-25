/** Declares the stable and unstable Home Manager flake inputs, tracking the matching nixpkgs channels. */
{ config, inputs, ... }:
{

  nucleus.inputs = {
    stable-home-manager = {
      url = "github:nix-community/home-manager/release-${config.flake.fleet.channels.stable}";
      inputs.nixpkgs.follows = "stable-nixpkgs";
    };
    unstable-home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "unstable-nixpkgs";
    };
  };

  flake.modules.nixos.stable-home-manager = {
    imports = [ inputs.stable-home-manager.nixosModules.home-manager ];
  };

  flake.modules.nixos.unstable-home-manager = {
    imports = [ inputs.unstable-home-manager.nixosModules.home-manager ];
  };
}
