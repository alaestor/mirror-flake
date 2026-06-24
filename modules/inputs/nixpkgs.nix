{ config, lib, ... } : {

  options.common = {
    nixpkgs-stable-version = lib.mkOption {
      type= lib.types.str;
      default = "26.05";
      description = "The version to which 'stable-nixpkgs' should be set.";
    };
  };

  config = {
    flake-file.inputs = {
      stable-nixpkgs.url   = "nixpkgs/nixos-${config.common.nixpkgs-stable-version}";
      unstable-nixpkgs.url = "nixpkgs/nixos-unstable";
    };
  };

}
