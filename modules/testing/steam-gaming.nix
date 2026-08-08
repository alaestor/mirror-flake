{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks.steam-gaming = import ../../tests/steam-gaming.nix {
        inherit inputs pkgs system;
      };
    };
}
