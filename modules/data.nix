{ lib, self, ... }:
let
  module-name = "data";

  /**
    flake.data provides utilites for interacting with the `data/` folder of the flake.
  */

in
{
  options = {
    flake.${module-name} = lib.mkOption {
      type = lib.types.attrsOf lib.types.unspecified;
      default = { };
      description = "Provides utilites for interacting with the `${module-name}/` folder of the flake.";
    };

  };

  config.flake."${module-name}" = rec {

    path = subpath : "${self}/${module-name}/${subpath}";

    read = subpath: builtins.readFile (path subpath);

    readJSON = subpath: builtins.fromJSON (read subpath);

    readLines = subpath: lib.splitString "\n" (read subpath);

    readNonEmptyLines = subpath: lib.filter (k: k != "") (readLines subpath);

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

      sshAuthorizedKeys = lib.concatMap identityLines (
        identities.administrative.ssh-keys
        ++ builtins.attrValues identities.host
      );

      textart.boykisser = path "textart/boykisser.txt";
    };
  };
}
