# DO-NOT-EDIT. This file was auto-generated using github:vic/flake-file.
# Use `nix run .#write-flake` to regenerate it.
{
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);

  inputs = {
    alpkgs = {
      url = "git+https://codeberg.org/alaestor/pkgs.git";
      inputs = {
        flake-file.follows = "flake-file";
        nixpkgs.follows = "nixpkgs";
      };
    };
    android-home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "android-nixpkgs";
    };
    android-nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    cryptid-nixpkgs.url = "nixpkgs/4c1018dae018162ec878d42fec712642d214fdfa";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    firefox-extensions-declarative = {
      url = "github:firefox-extensions-declarative/firefox-extensions-declarative";
      inputs.nixpkgs.follows = "unstable-nixpkgs";
    };
    flake-file.url = "github:vic/flake-file";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs = {
        home-manager.follows = "";
        nixpkgs.follows = "";
      };
    };
    import-tree.url = "github:vic/import-tree";
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      inputs = {
        home-manager.follows = "android-home-manager";
        nixpkgs.follows = "android-nixpkgs";
      };
    };
    nix-wrapper-modules = {
      url = "github:BirdeeHub/nix-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.xz";
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs = {
        home-manager.follows = "unstable-home-manager";
        nixpkgs.follows = "unstable-nixpkgs";
      };
    };
    stable-home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "stable-nixpkgs";
    };
    stable-nixpkgs.url = "nixpkgs/nixos-26.05";
    unstable-home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "unstable-nixpkgs";
    };
    unstable-nixpkgs.url = "nixpkgs/nixos-unstable";
    vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";
  };
}
