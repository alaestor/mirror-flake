/** Declares the stable and unstable nixpkgs flake inputs. */
{ config, ... } : {

  nucleus.inputs = {
    stable-nixpkgs.url   = "https://channels.nixos.org/nixos-${config.flake.fleet.channels.stable}/nixexprs.tar.zst";
    unstable-nixpkgs.follows = "nixpkgs";
  };

}
