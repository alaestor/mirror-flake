{ pkgs, root ? ./. }:
# Discover instruction macros and packaged programs recursively. Directive
# names are file basenames; directories organize source but do not namespace it.
let
  lib = pkgs.lib;
  mkMacro = name: description: instructions: {
    inherit description instructions;
    command = pkgs.writeShellApplication {
      name = "agent-directive-${name}";
      text = ''
        if [[ -n "''${1:-}" ]]; then
          printf '%s takes no arguments\n' ${lib.escapeShellArg name} >&2
          exit 2
        fi
        cat ${pkgs.writeText "agent-directive-${name}-instructions.md" instructions}
        printf '%s instructions loaded.\n' ${lib.escapeShellArg name} >&2
      '';
    };
  };
  discover = directory: extension:
    let
      walk = path:
        lib.concatMap (
          entry:
          let
            child = "${path}/${entry}";
            type = (builtins.readDir path).${entry};
          in
          if type == "directory" then
            walk child
          else if type == "regular" && lib.hasSuffix extension entry then
            [ {
              name = lib.removeSuffix extension entry;
              path = child;
            } ]
          else
            [ ]
        ) (builtins.attrNames (builtins.readDir path));
    in
    walk directory;
  macros = map (entry: {
    inherit (entry) name;
    value = (mkMacro entry.name "Inject ${lib.replaceStrings [ "-" ] [ " " ] entry.name} instructions" (
      builtins.readFile entry.path
    )) // { kind = "macro"; };
  }) (discover "${root}/macro" ".md");
  scripts = map (entry: {
    inherit (entry) name;
    value = (import entry.path { inherit pkgs mkMacro; }) // { kind = "script"; };
  }) (discover "${root}/script" ".nix");
  entries = macros ++ scripts;
  names = map (entry: entry.name) entries;
  duplicates = lib.filter (name: lib.count (candidate: candidate == name) names > 1) (lib.unique names);
in
if duplicates != [ ] then
  throw "Duplicate directive names: ${lib.concatStringsSep ", " duplicates}"
else
  builtins.listToAttrs entries
