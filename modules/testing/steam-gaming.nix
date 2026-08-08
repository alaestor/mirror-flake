{ inputs, self, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks.steam-gaming = import "${self}/tests/steam-gaming.nix" {
        inherit inputs pkgs system;
      };
    };
}
