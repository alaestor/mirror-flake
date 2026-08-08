{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks.plasma-composition = import ../../tests/plasma-composition.nix {
        inherit inputs pkgs system;
      };
    };
}
