{ fleet, ... }:
{
  nixOnDroid = [
    (import ./system.nix { tailnet = fleet.tailnets."0x04cc"; })
  ];
  homeManager = [ ];
}
