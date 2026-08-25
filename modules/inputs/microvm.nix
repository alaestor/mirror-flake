/** Declares the microvm.nix flake input used by the agent-vm mechanism. */
{ ... }:
{
  nucleus.inputs.microvm = {
    url = "github:microvm-nix/microvm.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
