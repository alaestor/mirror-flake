{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks.serve-contracts = import ../../tests/serve-contracts.nix {
        inherit inputs pkgs system;
      };
    };
}
