"""Claude Code context guard.

Reads a hook payload on stdin and decides whether the session is close enough
to its context limit to warrant a handoff, or far enough that the turn must be
stopped outright. Dispatches on `hook_event_name`, so one command serves every
event it is registered for.

Rationale: auto-compaction summarizes for narrative continuity and routinely
drops the details needed to resume work. This trades that summary for an
agent-written handoff produced while full context is still loaded, then stops
the turn once it exists rather than running the session further.

Claude Code reserves a fixed fraction of the window (observed ~16.5%,
regardless of how much of the rest is used) as its own auto-compact buffer —
that's the point at which it starts nagging about compaction and, eventually,
attempts one. The threshold here targets just under that reserve, so the
handoff pre-empts native compaction at the same point Claude Code would have
acted anyway, rather than racing it with an independent fraction. It also
keeps the "% until auto-compact" cosmetic countdown meaningful, since it now
roughly predicts when the handoff fires. A small margin is kept below that
line since the transcript this reads from lags the live count by a message or
two.

The threshold comes from the environment so the wrapper can raise it for 1M
sessions; hooks inherit the wrapper's environment.
"""

import json
import os
import sys
import time

DEFAULT_LIMIT = 200_000
THRESHOLD_FRACTION = 0.83


def state_dir():
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    path = os.path.join(base, "claude-context-guard")
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


def context_tokens(transcript_path):
    """Total context size from the most recent assistant usage record.

    The transcript is written asynchronously and may lag the live conversation
    by a message or two, so this reads low. The threshold compensates by
    sitting below the real limit.
    """
    if not transcript_path or not os.path.exists(transcript_path):
        return None
    total = None
    with open(transcript_path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            try:
                entry = json.loads(line)
            except ValueError:
                continue
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
    return total


def env_int(name, fallback):
    try:
        return int(os.environ[name])
    except (KeyError, ValueError):
        return fallback


def handoff_path(payload):
    root = payload.get("cwd") or os.getcwd()
    session = (payload.get("session_id") or "session")[:8]
    return os.path.join(root, ".claude", f"handoff-{session}.md")


def latest_handoff(payload):
    """Newest handoff left in this working directory, if any."""
    root = payload.get("cwd") or os.getcwd()
    directory = os.path.join(root, ".claude")
    try:
        names = [n for n in os.listdir(directory) if n.startswith("handoff-") and n.endswith(".md")]
    except OSError:
        return None
    paths = [os.path.join(directory, n) for n in names]
    return max(paths, key=os.path.getmtime) if paths else None


def handoff_request(payload, tokens, limit):
    return (
        f"Context is at {tokens:,} of {limit:,} tokens "
        f"({tokens / limit:.0%}). Auto-compaction is disabled for this session, "
        f"and the turn stops as soon as the handoff exists.\n\n"
        f"Write a handoff to {handoff_path(payload)} now, before doing "
        "anything else. Cover: the task and its current state, exact "
        "file:line targets, decisions already settled and why, what is still "
        "open, and what the next agent should do first. Omit concluded "
        "history and fixed bugs.\n\n"
        "The turn stops once the file exists, so the handoff is the last "
        "thing you do. Write it in one pass."
    )


def emit(obj):
    json.dump(obj, sys.stdout)
    sys.exit(0)


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        sys.exit(0)

    tokens = context_tokens(payload.get("transcript_path"))
    event = payload.get("hook_event_name")
    session = payload.get("session_id")

    # Blocking a proactive auto-compact leaves the conversation uncompacted,
    # which is the whole point. A compact triggered by an API context-limit
    # error fails the request instead, but the threshold below should fire
    # first.
    if event == "PreCompact":
        emit(
            {
                "decision": "block",
                "reason": (
                    "Auto-compaction is disabled for this session. Write or "
                    "update a handoff instead, then let the session end."
                ),
            }
        )

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

    limit = env_int("CC_CONTEXT_LIMIT", DEFAULT_LIMIT)
    threshold = env_int("CC_CONTEXT_THRESHOLD", int(limit * THRESHOLD_FRACTION))

    if tokens < threshold:
        sys.exit(0)

    if event == "PostToolUse":
        # Handing control back once the handoff exists is the point of the
        # threshold: the session is left resumable and paused right after the
        # handoff is written, rather than run further. The user can
        # technically resume from this, but they ought to be careful.
        if os.path.exists(handoff_path(payload)) and claim(session, "halted"):
            emit(
                {
                    "continue": False,
                    "stopReason": (
                        f"Handoff written to {handoff_path(payload)} at "
                        f"{tokens:,}/{limit:,} tokens. Turn stopped. It's"
                        "recommended you immediately start a fresh session"
                        "from the handoff."
                    ),
                }
            )
        if not claim(session, "warned"):
            sys.exit(0)
        emit(
            {
                "systemMessage": (
                    f"Context at {tokens:,}/{limit:,} ({tokens / limit:.0%}); "
                    "handoff requested, turn stops once it's written."
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
        if os.path.exists(handoff_path(payload)):
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
