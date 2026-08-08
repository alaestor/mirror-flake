{ inputs, self, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks.serve-contracts = import "${self}/tests/serve-contracts.nix" {
        inherit inputs pkgs system;
      };
    };
}
