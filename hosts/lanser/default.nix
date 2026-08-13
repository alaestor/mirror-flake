{ fleet, inputs, ... }:
{
  nixos = [
    ./hardware.nix
    ./networking.nix
    (import ./system.nix {
      inherit inputs;
      tailnet = fleet.tailnets."0x04cc";
    })
  ];

  homeManager = [ ];
}
