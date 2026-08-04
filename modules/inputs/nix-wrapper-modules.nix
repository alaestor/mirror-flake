{ inputs, ... }:
{
  imports = [ inputs.nix-wrapper-modules.flakeModules.wrappers ];

  nucleus.inputs.nix-wrapper-modules = {
    url = "github:BirdeeHub/nix-wrapper-modules";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
