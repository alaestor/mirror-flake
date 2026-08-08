{ lib }:
let
  # Each `known-hosts/<domain>.txt` file contains conventional known_hosts entries; adding a file automatically adds its domain.
  domains = map (name: lib.removeSuffix ".txt" name) (
    lib.attrNames (
      lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".txt" name) (
        builtins.readDir ./known-hosts
      )
    )
  );

  addKey = hosts: hostName: publicKey:
    hosts // {
      ${hostName} = (hosts.${hostName} or [ ]) ++ [ publicKey ];
    };

  parseLine = line:
    let
      fields = lib.splitString " " line;
    in
    {
      hostNames = lib.splitString "," (builtins.head fields);
      publicKey = lib.concatStringsSep " " (builtins.tail fields);
    };

  parseDomain = domain:
    lib.foldl'
      (
        hosts: line:
        let
          entry = parseLine line;
        in
        lib.foldl' (acc: hostName: addKey acc hostName entry.publicKey) hosts entry.hostNames
      )
      { }
      (lib.filter (line: line != "" && !(lib.hasPrefix "#" line)) (
        lib.splitString "\n" (builtins.readFile ./known-hosts/${domain}.txt)
      ));
in
lib.genAttrs domains parseDomain
