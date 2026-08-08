{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks.fleet = import ../../tests/fleet.nix {
        inherit inputs pkgs system;
      };
    };
}
