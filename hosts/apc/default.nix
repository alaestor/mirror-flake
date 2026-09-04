{ fleet, inputs, ... }:
{
  nixos = [
    ./hardware.nix
    (import ./networking.nix {
      inherit inputs;
      lan = fleet.lan;
      tailnet = fleet.tailnets."0x04cc";
    })
    (import ./system.nix {
      inherit inputs;
      lan = fleet.lan;
    })
  ];

  homeManager = [
    ./home/plasma.nix
    (import ./home/user.nix { inherit inputs; })
  ];
}
