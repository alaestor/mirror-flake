{ fleet, inputs, ... }:
{
  nixos = [
    ./hardware.nix
    ./networking.nix
    (import ./system.nix { inherit inputs; ports = fleet.ports.armatus; })
  ];

  homeManager = [
    (import ./home/user.nix { inherit inputs; })
  ];
}
