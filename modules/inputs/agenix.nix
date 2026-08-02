{ inputs, ... }:
{
  flake-file.inputs.agenix = {
    url = "github:ryantm/agenix";
    inputs.nixpkgs.follows = "unstable-nixpkgs";
    inputs.home-manager.follows = "unstable-home-manager";
  };

  flake.modules = {
    nixos.agenix.imports = [ inputs.agenix.nixosModules.default ];
    homeManager.agenix.imports = [ inputs.agenix.homeManagerModules.default ];
  };

  perSystem =
    { system, ... }:
    {
      packages.agenix = inputs.agenix.packages.${system}.agenix;
    };
}
