/**
  Typed, public, non-secret state shared by multiple repository consumers.

  Fleet records are declarative flake outputs. They describe shared facts, not
  evaluated hosts, credentials, storage paths, or machine topology.
*/
{ lib, ... }:
let
  inherit (lib) mkOption types;

  tailnetType = types.submodule {
    options = {
      coordinationUrl = mkOption {
        type = types.nonEmptyStr;
        description = "The Headscale or Tailscale coordination-server URL.";
      };

      dnsSuffix = mkOption {
        type = types.nonEmptyStr;
        description = "The tailnet DNS suffix.";
      };
    };
  };
in
{
  options.flake.fleet.channels = mkOption {
    type = types.attrsOf types.nonEmptyStr;
    default = { };
    description = "Named NixOS releases that the correspondingly named input families track.";
  };

  options.flake.fleet.tailnets = mkOption {
    type = types.attrsOf tailnetType;
    default = { };
    description = "Named public tailnet facts shared by fleet-aware composition modules.";
  };
}
