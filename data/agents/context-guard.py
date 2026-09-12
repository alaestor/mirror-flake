"""Harness-neutral context guard.

Reads a hook payload on stdin and decides whether the session is close enough
to its context limit to warrant a handoff, or far enough that further work must
be blocked outright. Dispatches on `hook_event_name`, so one command serves
every event it is registered for, and on a harness name given as `argv[1]`,
which selects how the transcript is read and how a turn is halted. `argv[1]`
may instead be `statusline`, which renders Claude Code's status line from the
same threshold the guard enforces rather than acting as a hook at all.

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

That margin is only a few thousand tokens, and the request below is advisory:
it rides along as `additionalContext` and competes with whatever the agent was
already doing. A single large tool result can therefore cross the threshold and
the harness's own hard ceiling within one turn, leaving no room to write the
handoff the request asked for. Lowering THRESHOLD_FRACTION widens the margin;
if that proves insufficient, the escalation is to reuse the PreCompact path's
`{"decision": "block"}` for the pre-handoff PostToolUse case, making the handoff
the only way forward rather than a suggestion. That also means dropping the
one-shot `warned` claim, since a block must fire on every attempt.
"""

import datetime
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


def statusline(payload):
    """Render the Claude Code status line and exit.

    Not a hook. Claude Code hands a status-line command a payload carrying
    `context_window`, which is computed from the live conversation rather than
    the transcript the hook path reads -- so this number leads the one the
    guard acts on instead of lagging it by a message or two.

    The countdown targets the guard's own threshold rather than the harness's
    compaction point, because the handoff is what actually interrupts the
    session. Reaching 0% here is the moment the guard starts asking. Sharing
    THRESHOLD_FRACTION with the guard is why this lives in the same file: two
    scripts would drift, and an indicator that disagrees with the event it
    predicts is worse than none.
    """
    window = payload.get("context_window") or {}
    used = window.get("total_input_tokens") or 0
    limit = env_int("CC_CONTEXT_LIMIT", window.get("context_window_size") or DEFAULT_LIMIT)
    threshold = env_int("AGENT_CONTEXT_THRESHOLD", int(limit * THRESHOLD_FRACTION))
    model = (payload.get("model") or {}).get("display_name") or ""

    if not used or threshold <= 0:
        print(model, end="")
        sys.exit(0)

    remaining = max(0, threshold - used) / threshold * 100
    # Dim until the budget is worth thinking about, then yellow, then red once
    # the handoff is close enough that starting new work is a bad idea.
    colour = "32" if remaining > 50 else "33" if remaining > 20 else "31"
    parts = [
        f"\033[2m{model}\033[0m",
        f"\033[2m{used // 1000}k/{threshold // 1000}k\033[0m",
        f"\033[{colour}m{remaining:.0f}% until handoff\033[0m",
    ]

    quota = plan_usage(payload)
    if quota:
        parts.append(f"\033[2m—\033[0m {quota}")

    print(" ".join(parts), end="")
    sys.exit(0)


def reset_in(stamp):
    """`resets_at` as a compact duration from now, or None if unusable.

    The status-line payload carries an ISO 8601 timestamp rather than an epoch
    count. Rendered coarsely on purpose: the point is whether the window turns
    over before the work does, not the exact minute.
    """
    if not stamp:
        return None
    try:
        when = datetime.datetime.fromisoformat(stamp)
    except (TypeError, ValueError):
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=datetime.timezone.utc)
    seconds = (when - datetime.datetime.now(datetime.timezone.utc)).total_seconds()
    if seconds <= 0:
        return None
    minutes = int(seconds // 60)
    if minutes < 60:
        return f"{minutes}m"
    hours, minutes = divmod(minutes, 60)
    if hours < 24:
        return f"{hours}h{minutes:02d}m"
    days, hours = divmod(hours, 24)
    return f"{days}d{hours:02d}h"


def plan_usage(payload):
    """The 5-hour and weekly plan windows, or "" when they do not apply.

    `rate_limits` is null for API-key, Bedrock, and Vertex auth, and absent
    until a response has carried the quota headers, so every field here is
    treated as optional. The model-scoped weekly windows the payload can also
    carry are deliberately ignored: which of them a plan exposes varies, and a
    status line that changes shape by plan is not worth reading.
    """
    limits = payload.get("rate_limits")
    if not isinstance(limits, dict):
        return ""

    rendered = []
    for label, key in (("5h", "five_hour"), ("7d", "seven_day")):
        window = limits.get(key)
        if not isinstance(window, dict):
            continue
        used = window.get("utilization")
        if not isinstance(used, (int, float)):
            continue
        colour = "32" if used < 50 else "33" if used < 80 else "31"
        resets = reset_in(window.get("resets_at"))
        suffix = f" \033[2m{resets}\033[0m" if resets else ""
        rendered.append(f"\033[2m{label}:\033[0m \033[{colour}m{used:.0f}%\033[0m{suffix}")

    return " \033[2m—\033[0m ".join(rendered)


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
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    harness = HARNESSES.get(mode)
    if harness is None and mode != "statusline":
        sys.exit(0)

    try:
        payload = json.load(sys.stdin)
    except ValueError:
        sys.exit(0)

    if mode == "statusline":
        statusline(payload)

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
