{ fleet, inputs, ... }:
{
  nixos = [
    ./hardware.nix
    inputs.self.modules.nixos.lxqt
    inputs.self.modules.nixos.auto-login
    (import ./networking.nix { lan = fleet.lan; })
    (import ./system.nix {
      inherit inputs;
      tailnet = fleet.tailnets."0x04cc";
      lan = fleet.lan;
    })
  ];

  homeManager = [ ];
}
