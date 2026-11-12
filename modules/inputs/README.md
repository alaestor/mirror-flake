## agenix

Declares the agenix flake input, for secret decryption at activation.

## alpkgs

Declares the alpkgs flake input, this author's personal package overlay.

## deepseek-harness

Declares the community Nix packaging for DeepSeek Harness (`dsh`).

Its own `nixConfig` advertises a Cachix substituter, which a consuming
flake does not inherit; without adding that substituter here or on the
host, `dsh` and its bundles are built from source.

## home-manager

Declares the stable and unstable Home Manager flake inputs, tracking the matching nixpkgs channels.

## microvm

Declares the microvm.nix flake input used by the agent-vm mechanism.

## nix-on-droid

Declares the nix-on-droid flake input and its pinned nixpkgs/Home Manager pair, for noblesse.

## nix-wrapper-modules

Declares the nix-wrapper-modules flake input and its wrappers flake module.

## nixpkgs

Declares the stable and unstable nixpkgs flake inputs.

## zed-cea

Declares the zed-cea flake input, this author's Cheat Engine Auto Assembler language tooling.
