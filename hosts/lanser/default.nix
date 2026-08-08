{ inputs, tailnet }:
{
  nixos = [
    ./hardware.nix
    ./networking.nix
    (import ./system.nix { inherit inputs tailnet; })
  ];

  homeManager = [ ];
}
