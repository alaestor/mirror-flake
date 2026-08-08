{ inputs, self, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks.home-environments = import "${self}/tests/home-environments.nix" {
        inherit inputs pkgs system;
      };
    };
}
