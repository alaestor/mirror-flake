{
  nucleus.inputs = {
    android-nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

    android-home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "android-nixpkgs";
    };

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      inputs.nixpkgs.follows = "android-nixpkgs";
      inputs.home-manager.follows = "android-home-manager";
    };
  };
}
