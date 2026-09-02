/**
  Exercises `flake.lib.agents.findGuardBashEnv` (`modules/mechanisms/libagents/libagents.nix`)
  against a synthetic stand-in for Claude Code's own exported `find` -> `bfs`
  shell function, so a future Claude Code build that reshapes that function
  enough to break the `sed`-based capture fails this build instead of only
  showing up as a silent stderr warning at agent runtime.
*/
{ inputs, pkgs, system }:
let
  agents = inputs.self.lib.agents;
  guard = agents.findGuardBashEnv pkgs;
  bash = pkgs.lib.getExe pkgs.bash;

  # Mirrors the real shell function observed from a live Claude Code session
  # (`declare -f find`) closely enough to exercise the same `sed` capture —
  # a leading `find ()` line, a body, and a delegated call — without
  # depending on Claude Code actually being installed to build this check.
  # Marks its own invocations in `$AGENT_FIND_GUARD_TEST_MARKER` rather than
  # a shell variable: the probe below observes it from inside a `$(...)`
  # capture, which runs `find` in a forked subshell, so a plain variable
  # increment would never make it back out.
  syntheticUpstream = pkgs.writeText "synthetic-upstream-find.sh" ''
    find ()
    {
        echo x >> "$AGENT_FIND_GUARD_TEST_MARKER";
        command find "$@"
    }
    export -f find
  '';

  # A standalone probe script rather than an inline string re-executed
  # through a second `bash -c`: fewer layers of quoting/re-parsing to get
  # wrong, and each case's real exit status is what the test itself sees.
  probe = pkgs.writeShellScript "agent-find-guard-probe" ''
    set -u
    case "$1" in
      with-upstream) source ${syntheticUpstream} ;;
    esac
    source ${guard}
    : > "$AGENT_FIND_GUARD_TEST_MARKER"
    err="$(find "''${@:2}" 2>&1 1>/dev/null)"
    status=$?
    echo "status=$status"
    echo "upstream_calls=$(wc -l < "$AGENT_FIND_GUARD_TEST_MARKER")"
    echo "stderr=$err"
  '';
in
pkgs.runCommand "agent-find-guard-test"
  {
    nativeBuildInputs = [ pkgs.findutils ];
  }
  ''
    set -u
    fail=0
    export AGENT_FIND_GUARD_TEST_MARKER="$PWD/upstream-calls.marker"

    check() {
      local desc="$1" input="$2" expect_status="$3" expect_calls="$4" expect_stderr_re="$5"
      local got_status got_calls got_stderr
      got_status="$(grep -oP '(?<=^status=).*' <<< "$input")"
      got_calls="$(grep -oP '(?<=^upstream_calls=).*' <<< "$input")"
      got_stderr="$(grep -oP '(?<=^stderr=).*' <<< "$input")"
      if [[ "$got_status" != "$expect_status" ]]; then
        echo "FAIL ($desc): expected exit $expect_status, got $got_status" >&2
        fail=1
      fi
      if [[ "$got_calls" != "$expect_calls" ]]; then
        echo "FAIL ($desc): expected $expect_calls upstream call(s), got $got_calls" >&2
        fail=1
      fi
      if [[ -n "$expect_stderr_re" && ! "$got_stderr" =~ $expect_stderr_re ]]; then
        echo "FAIL ($desc): stderr did not match /$expect_stderr_re/: $got_stderr" >&2
        fail=1
      fi
      if [[ -z "$expect_stderr_re" && "$got_stderr" == *"could not capture"* ]]; then
        echo "FAIL ($desc): spurious capture-failure warning: $got_stderr" >&2
        fail=1
      fi
    }

    # No pre-existing 'find' export (Codex's shape): the guard still blocks
    # root and otherwise defers to plain findutils; nothing to capture, so
    # no warning either.
    check "no upstream, root" \
      "$(${bash} ${probe} without-upstream /)" 1 0 "refusing to search filesystem root"
    check "no upstream, scoped" \
      "$(${bash} ${probe} without-upstream /nix -maxdepth 0)" 0 0 ""

    # A Claude-shaped exported 'find' function: the guard must capture it as
    # `_agent_find_upstream` (proven by the synthetic function's own call
    # counter, not just an exit status), print no capture-failure warning,
    # block root, and still delegate an in-tree call through to it.
    check "captured upstream, root" \
      "$(${bash} ${probe} with-upstream /)" 1 0 "refusing to search filesystem root"
    check "captured upstream, scoped" \
      "$(${bash} ${probe} with-upstream /nix -maxdepth 0)" 0 1 ""

    # FIND_ALLOW_ROOT=1 overrides the refusal and still reaches upstream.
    check "override, root" \
      "$(FIND_ALLOW_ROOT=1 ${bash} ${probe} with-upstream / -maxdepth 0)" 0 1 ""

    if (( fail )); then
      echo "agent-find-guard-test: one or more cases failed" >&2
      exit 1
    fi

    touch $out
  ''
