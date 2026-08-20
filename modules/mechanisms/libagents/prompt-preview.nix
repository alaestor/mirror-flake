/**
  # agents.promptPreview / `agent-prompt-preview`

  A read-only window onto `flake.lib.agents.mkPrompt`'s output, so a prompt
  can be inspected without starting a session.

  Harness feature modules (`claude-code.nix`, `codex.nix`, ...) publish each
  `(harness, variant)` prompt they resolve under
  `config.agents.promptPreview.<harness>.<variant>`, a plain `{ system;
  preamble; context; }` attrset — no isolation/VM concepts involved, this is
  purely the harness layer. The `agent-prompt-preview` package/app reads that
  attribute back out of an evaluated `homeConfigurations.<name>` via `nix
  eval`, printing each of the three depths separately.

  This module's `homeManager.agents-prompt-preview` output only declares the
  option; each harness feature module that writes to it
  (`claude-code.nix`, `codex.nix`) imports it directly, so either one is
  usable standalone without also pulling in a combining module. The module
  carries an explicit `key` (its own output attribute path, as in
  `ssh-known-hosts`) so importing it from more than one harness at once
  dedupes instead of failing at eval time with "option ... is already
  declared" — deferred/value-imported modules have no path to dedupe by
  otherwise.

  Usage: `nix run .#agent-prompt-preview -- claude plain` (add a third
  argument to pick a `homeConfigurations` name other than `user@apc`).
*/
{ ... }:
{
  flake.modules.homeManager.agents-prompt-preview =
    { lib, ... }:
    {
      # The interface may arrive through more than one harness feature module.
      key = "flake.modules.homeManager.agents-prompt-preview";

      options.agents.promptPreview = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.attrsOf (
            lib.types.submodule {
              options = {
                system = lib.mkOption {
                  type = lib.types.nullOr lib.types.path;
                  default = null;
                  description = "The `system`-depth prompt file, if this (harness, variant) uses one.";
                };
                preamble = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "The `preamble`-depth prompt text.";
                };
                context = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "The `context`-depth prompt text.";
                };
              };
            }
          )
        );
        default = { };
        description = ''
          Resolved `(harness, variant)` prompts, keyed by harness then
          variant, for the `agent-prompt-preview` tool. Populated by each
          harness feature module from its own `flake.lib.agents.mkPrompt`
          call; never read at runtime by a wrapper.
        '';
      };
    };

  perSystem =
    { pkgs, lib, ... }:
    let
      name = "agent-prompt-preview";
      package = pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = [ pkgs.nix ];
        text = ''
          harness=''${1:?usage: ${name} <harness> <variant> [homeConfiguration=user@apc]}
          variant=''${2:?usage: ${name} <harness> <variant> [homeConfiguration=user@apc]}
          home=''${3:-user@apc}
          attr=".#homeConfigurations.\"$home\".config.agents.promptPreview.\"$harness\".\"$variant\""

          for depth in system preamble context; do
            echo "=== $depth ==="
            nix eval --raw "$attr.$depth" 2>/dev/null || nix eval "$attr.$depth"
            echo
          done
        '';
      };
    in
    {
      packages.${name} = package;
      apps.${name} = {
        meta.description = "Print a resolved (harness, variant) prompt's system/preamble/context depths";
        program = lib.getExe package;
      };
    };
}
