{ inputs, ... }:
{
  nixos = [
    ./hardware.nix
    ./networking.nix
    (import ./system.nix { inherit inputs; })
  ];

  homeManager = [
    ./home/user.nix
  ];
}
