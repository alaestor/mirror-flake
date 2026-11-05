{ inputs, ... }:
{
  nixos = [
    ./hardware.nix
    ./networking.nix
    (import ./system.nix { inherit inputs; })
  ];

  homeManager = [
    (import ./home/user.nix { inherit inputs; })
  ];
}
