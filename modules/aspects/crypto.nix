/**
  Composes cryptographic capabilities, currently YubiKey tooling and stubs.
*/
{ self, ... }:
{
  flake.modules.nixos.crypto = {
    imports = [ self.modules.nixos.yubikey ];
  };
}
