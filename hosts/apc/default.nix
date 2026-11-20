{ fleet, inputs, ... }:
{
  nixos = [
    ./hardware.nix
    ./remapper.nix
    (import ./networking.nix {
      inherit inputs;
      lan = fleet.lan;
      tailnet = fleet.tailnets."0x04cc";
      ports = fleet.ports.apc;
      inherit (fleet.ports.shared) lm-studio;
    })
    (import ./system.nix {
      inherit inputs;
      lan = fleet.lan;
      ports = fleet.ports.apc;
    })
  ];

  homeManager = [
    ./home/plasma.nix
    (import ./home/user.nix {
      inherit inputs;
      tailnet = fleet.tailnets."0x04cc";
    })
  ];
}
