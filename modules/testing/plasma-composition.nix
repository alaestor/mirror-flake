{ inputs, self, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks.plasma-composition = import "${self}/tests/plasma-composition.nix" {
        inherit inputs pkgs system;
      };
    };
}
