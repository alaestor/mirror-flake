{ self, ... }:
{
  nixos = [
    ./storage.nix
    ./system.nix
    (import ./scripts.nix { inherit self; })
  ];
}
