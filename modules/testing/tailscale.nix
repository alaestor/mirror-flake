{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks.tailscale = import ../../tests/tailscale.nix {
        inherit inputs pkgs system;
      };
    };
}
