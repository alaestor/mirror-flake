/**
  Root nucleus declaration: supported systems, flake description, and the
  base nixpkgs/flake-parts inputs every other module builds on.
*/
{
  systems = [ "x86_64-linux" ];

  nucleus = {
    autoFollow.enable = true;
    description = "Alaestor Weissman's personal flake";
    inputs.nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";
    inputs.flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

}
