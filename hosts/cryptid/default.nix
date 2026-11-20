{ fleet, self, ... }:
{
  nixos = [
    ./storage.nix
    ./system.nix
    { services.openssh.ports = [ fleet.ports.cryptid.ssh ]; }
    (import ./scripts.nix { inherit self; })
  ];
}
