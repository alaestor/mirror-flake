{...}: {
  /**
    Generates a self-contained repository status report from scoped TODO and
    warning comments, grouped and filtered by marker, scope, or directory.

    Run from the flake root with `nix run .#mkstatus`.
  */
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    name = "mkstatus";
    package = pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [pkgs.git pkgs.nushell pkgs.ripgrep];
      text = ''
        exec ${lib.getExe pkgs.nushell} ${./mkstatus.nu} \
          --template ${./template.html} "$@"
      '';
    };
  in {
    packages.${name} = package;
    checks.${name} = pkgs.runCommand "${name}-test" {
      nativeBuildInputs = [pkgs.git pkgs.nushell pkgs.ripgrep];
    } ''
      nu ${./test.nu} ${./mkstatus.nu} ${./template.html}
      touch $out
    '';
    apps.${name} = {
      meta.description = "Generate a repository TODO and warning status report";
      program = lib.getExe package;
    };
  };
}
