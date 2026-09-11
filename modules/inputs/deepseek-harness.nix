/**
  Declares the community Nix packaging for DeepSeek Harness (`dsh`).

  Its own `nixConfig` advertises a Cachix substituter, which a consuming
  flake does not inherit; without adding that substituter here or on the
  host, `dsh` and its bundles are built from source.
*/
{ ... }:
{
  nucleus.inputs.deepseek-harness = {
    url = "github:Moraxyc/deepseek-harness.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
