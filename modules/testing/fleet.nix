{ inputs, self, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks.fleet = import "${self}/tests/fleet.nix" {
        inherit inputs pkgs system;
      };
    };
}
