/**
  Root nucleus declaration: supported systems, flake description, and the
  base nixpkgs/flake-parts inputs every other module builds on.
*/
{
  systems = [ "x86_64-linux" ];

  nucleus = {
    enable = true;
    description = "Alaestor Weissman's personal flake";
    inputs.nixpkgs.url = "nixpkgs/nixos-unstable";
    inputs.flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

}
