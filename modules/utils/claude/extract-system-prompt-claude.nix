{...}: {
  /**
    Extracts Claude Code's assembled system prompt verbatim by proxying a
    throwaway `claude -p` turn through a local HTTP server and dumping the
    `system` field of the request body.

    The captured preamble embeds machine-specific text, so run it from the
    directory whose environment should be reflected. Re-run after every Claude
    Code bump.

    ```
    nix run .#extract-system-prompt-claude \
      > data/programs/claude/claude-instructions-$(claude --version | cut -d' ' -f1)-full.md
    ```
  */
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    name = "extract-system-prompt-claude";
    package = pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [pkgs.python3];
      text = ''
        exec ${lib.getExe pkgs.python3} ${./extract-system-prompt-claude.py} "$@"
      '';
    };
  in {
    packages.${name} = package;
    apps.${name} = {
      meta.description = "Extract Claude Code's assembled system prompt";
      program = lib.getExe package;
    };
  };
}
