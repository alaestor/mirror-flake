{ inputs, self, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks.tailscale = import "${self}/tests/tailscale.nix" {
        inherit inputs pkgs system;
      };
    };
}
