/**
  # Repository data boundary

  Exposes public, non-secret repository data as `flake.data`. `path`, `read`,
  and `readJSON` resolve data relative to the flake root so consumers do not
  depend on their own source location. `vars` provides named normalized views
  for data shared by multiple modules.

  `data/` must never contain credentials or other secret material. Public
  identity metadata belongs here and is separated by operational role:

  - `identities.administrative` contains public administrator identities.
  - `identities.ssh-client` contains public per-host SSH client identities.
  - `identities.ssh-host` contains public SSH server identities.
  - `data/features/ssh-client/known-hosts.nix` constructs declarative public
    SSH known-host entries from domain-specific files.
  - `sshAdminKeys` contains only administrative SSH login identities.
  - `sshClientPublicKeys` contains only per-host SSH client identities.
  - `sshHostPublicKeys` contains only SSH host identities.

  Host identities must never be folded into `sshAdminKeys`. Encrypted
  private material belongs behind `flake.secrets`, not this interface.
*/
{ lib, self, ... }:
let
  inherit (lib) mkOption types;

  module-name = "data";

  varsType = types.submodule {
    options = {
      identities = mkOption {
        type = types.attrsOf types.unspecified;
        description = "Public identity metadata, by operational role.";
      };

      identityLines = mkOption {
        type = types.functionTo (types.listOf types.nonEmptyStr);
        description = "Significant lines of an identity file, without blanks or comments.";
      };

      administrativeAgeRecipients = mkOption {
        type = types.listOf types.nonEmptyStr;
        description = "Age recipients of the administrators.";
      };

      sshAdminKeys = mkOption {
        type = types.listOf types.nonEmptyStr;
        description = "Administrative SSH login identities.";
      };

      sshClientPublicKeys = mkOption {
        type = types.attrsOf types.nonEmptyStr;
        description = "Per-host SSH client identities, by host name.";
      };

      sshHostPublicKeys = mkOption {
        type = types.attrsOf types.nonEmptyStr;
        description = "SSH server identities, by host name.";
      };

      textart = mkOption {
        type = types.attrsOf types.nonEmptyStr;
        description = "Flake-rooted paths of named text-art files.";
      };
    };
  };

  dataType = types.submodule {
    options = {
      path = mkOption {
        type = types.functionTo types.nonEmptyStr;
        description = "Resolves a `data/`-relative subpath against the flake root.";
      };

      read = mkOption {
        type = types.functionTo types.str;
        description = "Contents of the `data/`-relative subpath.";
      };

      readJSON = mkOption {
        type = types.functionTo types.raw;
        description = "Parsed JSON contents of the `data/`-relative subpath.";
      };

      vars = mkOption {
        type = varsType;
        description = "Named normalized views for data shared by multiple modules.";
      };
    };
  };

in
{
  options = {
    flake.${module-name} = mkOption {
      type = dataType;
      default = { };
      description = "Public repository data and normalized consumer interfaces.";
    };

  };

  config.flake."${module-name}" = rec {

    path = subpath : "${self}/${module-name}/${subpath}";

    read = subpath: builtins.readFile (path subpath);

    readJSON = subpath: builtins.fromJSON (read subpath);

    /**
      Common representations of frequently used data files
    */
    vars = rec {
      identities = import (path "identities");

      identityLines = value:
        lib.filter
          (line: line != "" && !(lib.hasPrefix "#" line))
          (lib.splitString "\n" value);

      administrativeAgeRecipients =
        lib.concatMap identityLines identities.administrative.age-keys;

      sshAdminKeys =
        lib.concatMap identityLines identities.administrative.ssh-keys;

      sshClientPublicKeys =
        lib.mapAttrs (_: value: builtins.head (identityLines value)) identities.ssh-client;

      sshHostPublicKeys =
        lib.mapAttrs (_: value: builtins.head (identityLines value)) identities.ssh-host;

      textart.boykisser = path "textart/boykisser.txt";
    };
  };
}
