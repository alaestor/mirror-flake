{ inputs, ... }:
{
  nixos = [
    ./hardware.nix
    (import ./networking.nix { inherit inputs; })
    (import ./system.nix { inherit inputs; })
  ];

  homeManager = [
    ./home/plasma.nix
    ./home/user.nix
  ];
}
