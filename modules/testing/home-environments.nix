{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks.home-environments = import ../../tests/home-environments.nix {
        inherit inputs pkgs system;
      };
    };
}
