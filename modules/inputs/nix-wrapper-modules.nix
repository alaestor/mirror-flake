/** Declares the nix-wrapper-modules flake input and its wrappers flake module. */
{ inputs, ... }:
{
  imports = [ inputs.nix-wrapper-modules.flakeModules.wrappers ];

  nucleus.inputs.nix-wrapper-modules = {
    url = "github:BirdeeHub/nix-wrapper-modules";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
