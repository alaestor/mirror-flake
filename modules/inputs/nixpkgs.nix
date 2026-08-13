{ config, ... } : {

  nucleus.inputs = {
    stable-nixpkgs.url   = "nixpkgs/nixos-${config.flake.fleet.channels.stable}";
    unstable-nixpkgs.follows = "nixpkgs";
  };

}
