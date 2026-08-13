{ ... }:
{
  nixos = [
    ./hardware.nix
    ./networking.nix
    ./system.nix
  ];

  homeManager = [
    ./home/user.nix
  ];
}
