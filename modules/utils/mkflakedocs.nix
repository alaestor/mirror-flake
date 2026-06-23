{...}:
let
  name = "mkflakedocs";
in
{ /**
    Destructively regenerates `README.md` files recursively by extracting `/**` doc-strings from nix files. By default, it only recurses subfolders and doesn't generate a top-level `./README.md` unless the `--include-root` argument is used.

    E.g. in flake root:
    ```
    nix run mkflakedocs
    ```
  */
  perSystem = {pkgs, lib, ...} : {

    apps."${name}".program = builtins.toString (pkgs.writeShellScript "${name}" ''
      set -euo pipefail
      echo "Populating README.md files from nix file doc-strings..."
      ${lib.getExe pkgs.nushell} ${./mkflakedocs.nu}
    '');
  };
}
