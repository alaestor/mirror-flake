/** Declares the nix-on-droid flake input and its pinned nixpkgs/Home Manager pair, for noblesse. */
{
  nucleus.inputs = {
    android-nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

    android-home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "android-nixpkgs";
    };

    nix-on-droid = {
      url = "git+https://git.0x04.cc/alaestor/fork-nix-on-droid.git?ref=better-cross-compile-1";
      inputs.nixpkgs.follows = "android-nixpkgs";
      inputs.home-manager.follows = "android-home-manager";
    };
  };
}
