{ fleet, ... }:
{
  nixOnDroid = [
    (import ./system.nix {
      tailnet = fleet.tailnets."0x04cc";
      ports = fleet.ports.noblesse;
      builderSshPort = fleet.ports.apc.ssh;
    })
  ];
  homeManager = [ ];
}
