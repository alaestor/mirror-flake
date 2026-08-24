/**
  # flake.lib.agents.{mkSelectorLoop, mkHarnessWrappers}

  Implemented per the deviation recorded in `.claude/handoff-472dce40.md`:
  an earlier design's literal "harness factory" (model/effort as reserved
  cross-harness words,
  `native` as a selector) was replaced with this narrower design after
  discussion. What genuinely generalizes across `cc`/`ccs`/`cx`/`cxs` turned
  out to be smaller than the guide scoped it: harnesses keep their own
  selector vocabulary (`haiku|sonnet|opus` vs `luna|terra|sol`, `--effort` vs
  `-c model_reasoning_effort=`, ...) as their own case arms, handed to this
  factory as literal bash text — not a declarative selector DSL, which would
  be over-engineering for text that already differs per harness in both
  membership and downstream flag shape.

  Two pieces:

  - `mkSelectorLoop` — the shared `while/case` skeleton: `--` handling,
    "later selector wins" (implicit case-statement ordering — nothing here
    enforces it, it falls out of `case` re-matching each arg once), and the
    one line of `--help` footer text that was identically duplicated between
    `claude-code.nix` and `codex.nix`. Everything else in a harness's
    `--*-help` output (usage line, per-selector explanations) stays with the
    harness, since that text is harness-specific.

  - `mkHarnessWrappers` — builds a `<name>-native` package (the bare,
    unsandboxed session invocation: selector parsing through the final
    exec) and a `<name>` package (a thin dispatcher that either execs
    `<name>-native` directly, when `sandbox` is null, or hands off to
    whatever `sandbox` returns — bubblewrap today, a microVM in a later
    phase). `native` is no longer a selector word: running `<name>-native`
    directly *is* the bypass, so there is no runtime `sandbox` flag to
    thread through one script and no collision surface to guard with an
    eval-time assertion (the guide's Phase 3 called for one; it has nothing
    left to protect under this design — see the handoff for why that
    requirement was dropped rather than carried forward speculatively).

  Forward-looking Phase 3 pieces from the guide (`stateDirs`, `components`,
  `needs` fields for the VM layer) are intentionally absent here — Phase 4
  hasn't clarified what the VM layer needs from a harness declaration yet,
  and guessing ahead of it risks the wrong shape. Don't add them speculatively.
*/
{ lib, ... }:
let
  selectorFooter = "selectors are recognized in any order before --; later selectors replace earlier ones";

  # `caseArms` is raw bash text: one or more `pattern) ... ;;` case arms,
  # already indented for their position inside the `case "$1" in ... esac`
  # this generates. `argsVar` is the bash array that both raw passthrough
  # arguments (the catch-all arm) and `--`'s remainder are appended to.
  mkSelectorLoop =
    {
      caseArms,
      helpFlag,
      helpLines,
      argsVar ? "passthrough",
    }:
    ''
      while (( $# > 0 )); do
        case "$1" in
      ${caseArms}
          ${helpFlag})
      ${lib.concatMapStringsSep "\n" (line: "      echo ${lib.escapeShellArg line}") helpLines}
            echo ${lib.escapeShellArg selectorFooter}
            exit 0
            ;;
          --)
            shift
            ${argsVar}+=( "$@" )
            break
            ;;
          *) ${argsVar}+=( "$1" ) ;;
        esac
        shift
      done
    '';

  # `nativeText` is the full body of the unsandboxed session invocation —
  # selector loop through the final `exec`. `sandbox`, if given, is a
  # function from the built `-native` package to the bash text of the
  # dispatcher's body (typically an `exec` into bubblewrap or, later, a VM
  # handoff); if null, `<name>` is a plain `exec` into `<name>-native`.
  mkHarnessWrappers =
    pkgs:
    {
      name,
      nativeText,
      runtimeInputs ? [ ],
      excludeShellChecks ? [ ],
      sandbox ? null,
    }:
    let
      native = pkgs.writeShellApplication {
        name = "${name}-native";
        inherit runtimeInputs;
        excludeShellChecks = [ "SC2016" ] ++ excludeShellChecks;
        text = nativeText;
      };
      wrapped = pkgs.writeShellApplication {
        inherit name;
        excludeShellChecks = [ "SC2016" ] ++ excludeShellChecks;
        runtimeInputs = [ native ] ++ runtimeInputs;
        text =
          if sandbox == null then
            ''
              exec ${lib.getExe native} "$@"
            ''
          else
            sandbox native;
      };
    in
    {
      inherit native wrapped;
    };
in
{
  flake.lib.agents = {
    inherit mkSelectorLoop mkHarnessWrappers;
  };
}
