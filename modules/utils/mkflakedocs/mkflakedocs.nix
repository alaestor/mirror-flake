{...}:
let
  name = "mkflakedocs";
in
{
  /**
    Destructively regenerates `README.md` files recursively by extracting `/**` doc-strings from nix files. By default, it only recurses subfolders and doesn't generate a top-level `./README.md` unless the `--include-root` argument is used.

    Run inside a Git worktree. Processes tracked and nonignored untracked
    files under the current directory, honoring Git's ignore rules.

    E.g. in flake root:
    ```
    nix run mkflakedocs
    ```
  */
  perSystem = {pkgs, lib, ...} : let
    package = pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [pkgs.git];
      text = ''
        echo "Populating README.md files from nix file doc-strings..."
        exec ${lib.getExe pkgs.nushell} ${./mkflakedocs.nu} "$@"
      '';
    };
  in {

    checks.${name} = pkgs.runCommand "${name}-test" {
      nativeBuildInputs = [pkgs.git pkgs.nushell];
    } ''
      nu ${./test.nu} ${./mkflakedocs.nu}
      touch $out
    '';

    apps."${name}" = {
      meta.description = "Destructively regenerates `README.md` files";
      program = lib.getExe package;
    };

  };
}
