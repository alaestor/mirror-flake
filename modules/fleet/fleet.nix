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

  lanType = types.submodule {
    options = {
      cidr = mkOption {
        type = types.nonEmptyStr;
        description = ''
          The general LAN's CIDR. Not every physical network in the fleet:
          a direct-attach link between two specific machines (e.g. a
          dedicated NIC-to-NIC subnet) is that pair's own concern, not a
          fleet fact.
        '';
      };

      gateway = mkOption {
        type = types.nonEmptyStr;
        description = "The general LAN's default gateway address.";
      };

      nas = mkOption {
        type = types.nonEmptyStr;
        description = ''
          The NAS's address on the general LAN. A host reaching the NAS over
          a different, direct-attach link (not this LAN) has its own address
          for it and does not consume this fact.
        '';
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

  options.flake.fleet.lan = mkOption {
    type = types.nullOr lanType;
    default = null;
    description = "The general LAN's shared facts, if the fleet has one.";
  };

  options.flake.fleet.knownHosts = mkOption {
    type = types.attrsOf (types.attrsOf (types.listOf types.nonEmptyStr));
    default = { };
    description = ''
      Fleet-wide SSH known-hosts appendix, shaped like
      `ssh-client.knownHosts`: domain, then hostname (as it would appear in
      `known_hosts`), then a list of `type base64-data...` keys.
    '';
  };
}
