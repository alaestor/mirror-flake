"""Harness-neutral context guard.

Reads a hook payload on stdin and decides whether the session is close enough
to its context limit to warrant a handoff, or far enough that further work must
be blocked outright. Dispatches on `hook_event_name`, so one command serves
every event it is registered for, and on a harness name given as `argv[1]`,
which selects how the transcript is read and how a turn is halted.

Rationale: auto-compaction summarizes for narrative continuity and routinely
drops the details needed to resume work. This trades that summary for an
agent-written handoff produced while full context is still loaded, then stops
the turn once it exists rather than running the session further.

Both harnesses speak the same hook protocol -- same payload fields, same
`hookSpecificOutput.additionalContext` -- so only two things differ:

* Transcript accounting. Claude Code writes per-message `usage` records whose
  fields sum to the live context. Codex writes `token_count` records carrying
  both `last_token_usage` (the most recent request, which *is* the context) and
  `total_token_usage` (cumulative across every turn, which is not); summing the
  latter the way Claude's fields are summed reads in the millions. Codex also
  records `model_context_window`, so its limit needs no environment variable.

* Halting. Claude Code honours `{"continue": false}`. Codex ignores it -- the
  turn runs to completion -- and needs `{"decision": "block"}`, which turns the
  tool result into an error carrying the reason and makes the model abandon the
  sequence. See `__reference/codex-hooks-trust/FINDINGS.md`.

Claude Code reserves a fixed fraction of the window (observed ~16.5%,
regardless of how much of the rest is used) as its own auto-compact buffer --
that's the point at which it starts nagging about compaction and, eventually,
attempts one. The threshold here targets just under that reserve, so the
handoff pre-empts native compaction at the same point Claude Code would have
acted anyway, rather than racing it with an independent fraction. A small
margin is kept below that line since the transcript this reads from lags the
live count by a message or two.
"""

import glob
import json
import os
import sys
import time

DEFAULT_LIMIT = 200_000
THRESHOLD_FRACTION = 0.83

# Guard-written handoffs live apart from the `handoff.md` the handoff skill
# writes: these are recoverables produced under duress, not a deliberate
# artefact, and mixing them would make "the handoff" ambiguous.
SESSION_DIR = os.path.join(".agents", "session")


def state_dir():
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    path = os.path.join(base, "agent-context-guard")
    os.makedirs(path, exist_ok=True)
    return path


def claim(session_id, tag):
    """Return True the first time a (session, tag) pair is claimed.

    Keeps the guard from repeating itself on every tool call once a session is
    over a threshold.
    """
    if not session_id:
        return True
    marker = os.path.join(state_dir(), f"{session_id}.{tag}")
    try:
        os.close(os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
    except FileExistsError:
        return False
    return True


def transcript_entries(transcript_path):
    if not transcript_path or not os.path.exists(transcript_path):
        return
    with open(transcript_path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            try:
                yield json.loads(line)
            except ValueError:
                continue


def claude_context(transcript_path):
    """Total context size from the most recent assistant usage record.

    The transcript is written asynchronously and may lag the live conversation
    by a message or two, so this reads low. The threshold compensates by
    sitting below the real limit.
    """
    total = None
    for entry in transcript_entries(transcript_path):
        usage = (entry.get("message") or {}).get("usage")
        if not isinstance(usage, dict):
            continue
        total = sum(
            usage.get(field, 0)
            for field in (
                "input_tokens",
                "cache_creation_input_tokens",
                "cache_read_input_tokens",
            )
        )
    return total, env_int("CC_CONTEXT_LIMIT", DEFAULT_LIMIT)


def codex_context(transcript_path):
    """Live context and window from the most recent rollout records.

    `last_token_usage` describes the most recent request, so its input plus
    output is what the next request will carry. `total_token_usage` is
    cumulative and deliberately ignored.
    """
    total = None
    limit = None
    for entry in transcript_entries(transcript_path):
        window = find_key(entry, "model_context_window")
        if isinstance(window, int) and window > 0:
            limit = window
        usage = find_key(entry, "last_token_usage")
        if isinstance(usage, dict):
            total = usage.get("input_tokens", 0) + usage.get("output_tokens", 0)
    return total, limit or env_int("CODEX_CONTEXT_LIMIT", DEFAULT_LIMIT)


def find_key(entry, key):
    """Locate `key` anywhere in a shallow rollout record.

    Rollout entries wrap their payload differently depending on record type
    (`payload`, `info`, or the top level), so this checks the obvious nestings
    rather than hard-coding one shape that a Codex release could rename.
    """
    if not isinstance(entry, dict):
        return None
    if key in entry:
        return entry[key]
    for nested in ("payload", "info", "data"):
        inner = entry.get(nested)
        if isinstance(inner, dict):
            found = find_key(inner, key)
            if found is not None:
                return found
    return None


HARNESSES = {
    "claude": {
        "read": claude_context,
        # Claude Code stops the turn outright and reports `stopReason` to the
        # user; the session stays resumable.
        "halt": lambda reason: {"continue": False, "stopReason": reason},
    },
    "codex": {
        "read": codex_context,
        # Codex ignores `continue: false`. Blocking makes every further tool
        # call fail with this reason, which the model treats as a wall.
        "halt": lambda reason: {"decision": "block", "reason": reason},
    },
}


def env_int(name, fallback):
    try:
        return int(os.environ[name])
    except (KeyError, ValueError):
        return fallback


def session_root(payload):
    """The cwd the session actually started in, independent of later `cd`s.

    `payload["cwd"]` is re-read live on every hook event, so if the agent
    changes directory mid-session (e.g. `cd`ing into a subproject) later
    events see that subdirectory instead of the root the session began in.
    The first cwd seen for a session is cached to `state_dir()` and reused
    for the rest of the session, so the handoff always lands in one place.
    """
    session = payload.get("session_id")
    cwd = payload.get("cwd") or os.getcwd()
    if not session:
        return cwd
    marker = os.path.join(state_dir(), f"{session}.cwd")
    try:
        with open(marker, "x", encoding="utf-8") as handle:
            handle.write(cwd)
        return cwd
    except FileExistsError:
        with open(marker, encoding="utf-8") as handle:
            return handle.read().strip() or cwd


def session_started(payload):
    """Epoch seconds of the first hook event seen for this session.

    Used to tell a handoff this session wrote from one an earlier session left
    behind, since the agent picks the filename and the guard cannot predict it.
    """
    session = payload.get("session_id")
    if not session:
        return time.time()
    marker = os.path.join(state_dir(), f"{session}.cwd")
    try:
        return os.path.getmtime(marker)
    except OSError:
        return time.time()


def session_dir(payload):
    return os.path.join(session_root(payload), SESSION_DIR)


def handoffs(payload):
    return sorted(
        glob.glob(os.path.join(session_dir(payload), "*.md")),
        key=os.path.getmtime,
    )


def handoff_written(payload):
    """True once this session has left a handoff behind.

    Filename is the agent's to choose, so existence is judged by mtime against
    the session's own start rather than by a path the guard computed.
    """
    started = session_started(payload)
    return any(os.path.getmtime(path) >= started for path in handoffs(payload))


def latest_handoff(payload):
    """Newest handoff left in this working directory, if any."""
    found = handoffs(payload)
    return found[-1] if found else None


def handoff_request(payload, tokens, limit):
    directory = session_dir(payload)
    stamp = time.strftime("%Y%m%dT%H%M%S")
    return (
        f"Context is at {tokens:,} of {limit:,} tokens ({tokens / limit:.0%}). "
        "Auto-compaction is disabled for this session, and further work is stopped as soon as the handoff exists.\n\n"
        f"Write a handoff to {directory}/{stamp}-<topic>.md now, without doing anything else. "
        "Replace <topic> with a short kebab-case slug naming what this session was working on, "
        "so the filename sorts chronologically and reads as a subject line.\n\n"
        "You need to think about how best to direct the new session to pick up from where you're leaving off. "
        "Cover: the task and its current state, decisions already settled and why, what's open, "
        "and what the next agent should do first. Recommend what files the next session should read "
        "to prepare for its task; recommend against certain files you think they might try to read but "
        "that you know aren't relevant and say what they are instead. Mention gotcha's and hickups "
        "you ran into, but only if you expect they will encounter them in the pending work. "
        "Omit concluded history and fixed bugs.\n\n"
        "Try to give good advice. The point of this is to set them up for success by providing high-value, "
        "high signal-to-noise information by weighting your experiences against future relevancy. "
        "This isn't a compaction summary: you're give the next _you_ what they need to hit the ground running.\n\n"
        "Write it in one pass, then end your turn immediately without further tool calls: "
        "the handoff is the last thing you do."
    )


def emit(obj):
    json.dump(obj, sys.stdout)
    sys.exit(0)


def main():
    harness = HARNESSES.get(sys.argv[1] if len(sys.argv) > 1 else "")
    if harness is None:
        sys.exit(0)

    try:
        payload = json.load(sys.stdin)
    except ValueError:
        sys.exit(0)

    tokens, limit = harness["read"](payload.get("transcript_path"))
    event = payload.get("hook_event_name")
    session = payload.get("session_id")

    # Blocking a proactive auto-compact leaves the conversation uncompacted,
    # which is the whole point. A compact triggered by an API context-limit
    # error fails the request instead, but the threshold below should fire
    # first. Covers both triggers (`payload["trigger"]` is "auto" or
    # "manual") -- a `/compact` run by hand gets redirected the same as a
    # proactive one, reusing the same instructions PostToolUse/Stop give once
    # the threshold is crossed, rather than a bare "write a handoff" nudge
    # with no path or content guidance.
    if event == "PreCompact":
        if tokens is not None:
            reason = handoff_request(payload, tokens, limit)
        else:
            reason = (
                "Auto-compaction is disabled for this session. Write or "
                "update a handoff instead, then let the session end."
            )
        emit({"decision": "block", "reason": reason})

    # Announce a prior handoff so the user can refer to it without naming the
    # path. Deliberately not read on sight: a stale handoff is worse than none,
    # and reading it unprompted would spend the context it exists to conserve.
    if event == "SessionStart":
        previous = latest_handoff(payload)
        if not previous:
            sys.exit(0)
        age_hours = (time.time() - os.path.getmtime(previous)) / 3600
        emit(
            {
                "hookSpecificOutput": {
                    "hookEventName": "SessionStart",
                    "additionalContext": (
                        f"A handoff from an earlier session exists at "
                        f"{previous} (written {age_hours:.0f}h ago). Do not "
                        "read it unless the user asks you to pick up from it; "
                        "if they refer to 'the handoff', this is the file."
                    ),
                },
            }
        )

    if tokens is None:
        sys.exit(0)

    threshold = env_int("AGENT_CONTEXT_THRESHOLD", int(limit * THRESHOLD_FRACTION))

    if tokens < threshold:
        sys.exit(0)

    if event == "PostToolUse":
        # Handing control back once the handoff exists is the point of the
        # threshold: the session is left resumable and paused right after the
        # handoff is written, rather than run further. The user can
        # technically resume from this, but they ought to be careful.
        if handoff_written(payload) and claim(session, "halted"):
            emit(
                harness["halt"](
                    f"Handoff written at {tokens:,}/{limit:,} tokens. Stopping here. "
                    "It's recommended you immediately start a fresh session from the handoff."
                )
            )
        if not claim(session, "warned"):
            sys.exit(0)
        emit(
            {
                "systemMessage": (
                    f"Context at {tokens:,}/{limit:,} ({tokens / limit:.0%}); "
                    "handoff requested, work stops once it's written."
                ),
                "hookSpecificOutput": {
                    "hookEventName": "PostToolUse",
                    "additionalContext": handoff_request(payload, tokens, limit),
                },
            }
        )

    if event == "Stop":
        # Stop fires after PostToolUse has already asked, so this only covers
        # turns that crossed the threshold without running a tool.
        if payload.get("stop_hook_active") or not claim(session, "stop-asked"):
            sys.exit(0)
        if handoff_written(payload):
            sys.exit(0)
        emit(
            {
                "hookSpecificOutput": {
                    "hookEventName": "Stop",
                    "additionalContext": handoff_request(payload, tokens, limit),
                },
            }
        )

    sys.exit(0)


if __name__ == "__main__":
    main()
