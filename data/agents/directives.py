"""Resolve explicit prompt directives without vendor skill machinery."""

import argparse
from datetime import datetime, timezone
import difflib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid


SINGLE_PREFIX = "^^"
BOUNDED = (("^^{", "}"),)
ESCAPE = "\\"
MAX_OUTPUT = 180_000
MAX_CONTEXT = 180_000


def log_event(batch, source, name, cwd, outcome, **details):
    """Append metadata, never prompt arguments or command output."""
    base = os.environ.get("XDG_STATE_HOME")
    if not base or not os.path.isabs(base):
        base = os.path.expanduser("~/.local/state")
    directory = Path(base) / "agent-directives"
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    event = {
        "time": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
        "batch": batch,
        "source": source,
        "name": name,
        "cwd": os.path.abspath(cwd),
        "outcome": outcome,
        **details,
    }
    data = (json.dumps(event) + "\n").encode("utf-8")
    fd = os.open(directory / "events.jsonl", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        if os.write(fd, data) != len(data):
            raise OSError("short directive log write")
    finally:
        os.close(fd)


def lex(prompt):
    """Yield (name, raw argument text) in prompt order."""
    index = 0
    while index < len(prompt):
        if prompt.startswith(ESCAPE + SINGLE_PREFIX, index):
            index += len(ESCAPE + SINGLE_PREFIX)
            continue
        bounded = next(((start, end) for start, end in BOUNDED if prompt.startswith(start, index)), None)
        if bounded:
            start, end = bounded
            close = prompt.find(end, index + len(start))
            if close < 0:
                index += len(start)
                continue
            body = prompt[index + len(start):close].lstrip()
            split = next((offset for offset, char in enumerate(body) if char.isspace()), len(body))
            name = body[:split]
            args = body[split + 1:] if split < len(body) else ""
            if name:
                yield name, args
            index = close + len(end)
            continue
        if prompt.startswith(SINGLE_PREFIX, index):
            start = index + len(SINGLE_PREFIX)
            end = start
            while end < len(prompt) and not prompt[end].isspace():
                end += 1
            if end > start:
                yield prompt[start:end], ""
            index = end
            continue
        index += 1


def catalogue(path):
    entries = json.loads(path.read_text(encoding="utf-8"))
    result = {}
    for entry in entries:
        name = entry["name"]
        if name in result or "/" in name or not name:
            raise ValueError(f"invalid or duplicate directive name: {name}")
        if ("command" in entry) == ("alias" in entry):
            raise ValueError(f"directive {name} needs exactly one command or alias")
        result[name] = entry
    for name, entry in result.items():
        if "alias" in entry and (entry["alias"] not in result or "alias" in result[entry["alias"]]):
            raise ValueError(f"directive {name} has an invalid alias")
    return result


def resolve(items, entries, cwd, source):
    items = list(items)
    batch = uuid.uuid4().hex

    def record(name, outcome, **details):
        try:
            log_event(batch, source, name, cwd, outcome, **details)
        except OSError as error:
            return f"Could not write directive log: {error}."
        return None

    unknown = []
    for name, _ in items:
        if name not in entries:
            near = difflib.get_close_matches(name, entries, n=3)
            suggestion = f" Did you mean: {', '.join(near)}?" if near else ""
            unknown.append(f"Unknown directive {name!r}.{suggestion}")
            log_error = record("<unknown>", "unknown")
            if log_error:
                unknown.append(log_error)
    if unknown:
        return "", "\n".join(unknown), False

    sections = []
    receipts = []
    for name, args in items:
        entry = entries[name]
        if "alias" in entry:
            entry = entries[entry["alias"]]
        log_error = record(name, "started")
        if log_error:
            receipts.append(log_error + " No command was started.")
            break
        started = time.monotonic()
        outcome = "ok"
        details = {}
        stop = False
        try:
            result = subprocess.run(
                [entry["command"], args], cwd=cwd,
                capture_output=True, text=True, timeout=30, check=False,
            )
            if result.returncode:
                outcome = "failed"
                details["exit_code"] = result.returncode
                detail = result.stderr.strip()
                suffix = f"\n{detail}" if detail else ""
                message = f"Directive {name!r} failed (exit {result.returncode}). Its side effects may have occurred.{suffix}"
                receipts.append(message)
                stop = True
            elif len(result.stdout) > MAX_OUTPUT:
                outcome = "output_limit"
                message = f"Directive {name!r} produced too much output; nothing was injected. Its side effects may have occurred."
                receipts.append(message + (f"\n{result.stderr.rstrip()}" if result.stderr.strip() else ""))
                stop = True
            elif result.stdout:
                section = f"[Directive {name}]\n{result.stdout.rstrip()}"
                if sum(map(len, sections)) + len(section) > MAX_CONTEXT:
                    outcome = "context_limit"
                    message = f"Directive {name!r} exceeded the context budget; its output was omitted. Its side effects may have occurred."
                    receipts.append(message + (f"\n{result.stderr.rstrip()}" if result.stderr.strip() else ""))
                    stop = True
                else:
                    sections.append(section)
            if not stop:
                note = result.stderr.rstrip()
                receipts.append(f"Directive {name!r}:\n{note}" if note else f"Directive {name!r} completed.")
        except subprocess.TimeoutExpired as error:
            outcome = "timeout"
            message = f"Directive {name!r} timed out. Its side effects may have occurred."
            detail = error.stderr or ""
            if isinstance(detail, bytes):
                detail = detail.decode("utf-8", errors="replace")
            receipts.append(message + (f"\n{detail.rstrip()}" if detail.strip() else ""))
            stop = True
        except OSError as error:
            outcome = "start_error"
            message = f"Directive {name!r} could not start: {error}."
            receipts.append(message)
            stop = True
        details["duration_ms"] = round((time.monotonic() - started) * 1000)
        log_error = record(name, outcome, **details)
        if log_error:
            receipts.append(log_error + " The command may have changed files.")
            stop = True
        if stop:
            break
    else:
        return "\n\n".join(sections), "\n\n".join(receipts), True
    return "", "\n\n".join(receipts), False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalogue", type=Path, required=True)
    sub = parser.add_subparsers(dest="mode")
    sub.add_parser("hook").add_argument("harness", choices=("claude", "codex"))
    sub.add_parser("expand").add_argument("--json", action="store_true", required=True)
    sub.add_parser("list").add_argument("--json", action="store_true", required=True)
    run_parser = sub.add_parser("run")
    run_parser.add_argument("name")
    run_parser.add_argument("arguments", nargs="?", default="")
    args = parser.parse_args()
    entries = catalogue(args.catalogue)
    if args.mode == "list":
        print(json.dumps([{"name": name, **item} for name, item in entries.items()]))
    elif args.mode == "expand":
        items = json.load(sys.stdin)
        context, receipt, ok = resolve([(item["name"], item.get("args", "")) for item in items], entries, os.getcwd(), "expand")
        print(json.dumps({"context": context, "receipt": receipt, "ok": ok}))
        if not ok:
            raise SystemExit(2)
    elif args.mode == "run":
        batch = uuid.uuid4().hex
        cwd = os.getcwd()
        entry = entries.get(args.name)
        if entry is None:
            try:
                log_event(batch, "terminal", "<unknown>", cwd, "unknown")
            except OSError as error:
                parser.error(f"unknown directive: {args.name}; could not write directive log: {error}")
            parser.error(f"unknown directive: {args.name}")
        if "alias" in entry:
            entry = entries[entry["alias"]]
        try:
            log_event(batch, "terminal", args.name, cwd, "started")
        except OSError as error:
            parser.error(f"could not write directive log: {error}")
        started = time.monotonic()
        try:
            result = subprocess.run([entry["command"], args.arguments], check=False)
            outcome = "ok" if result.returncode == 0 else "failed"
            exit_code = result.returncode
        except OSError as error:
            print(f"Directive {args.name!r} could not start: {error}", file=sys.stderr)
            outcome = "start_error"
            exit_code = 127
        try:
            log_event(
                batch, "terminal", args.name, cwd, outcome,
                exit_code=exit_code, duration_ms=round((time.monotonic() - started) * 1000),
            )
        except OSError as error:
            print(f"Could not write directive log: {error}. The command may have changed files.", file=sys.stderr)
            raise SystemExit(2)
        raise SystemExit(exit_code)
    elif args.mode == "hook":
        payload = json.load(sys.stdin)
        if payload.get("hook_event_name") != "UserPromptSubmit":
            return
        context, receipt, ok = resolve(lex(payload.get("prompt", "")), entries, payload.get("cwd") or os.getcwd(), args.harness)
        if not ok:
            print(receipt, file=sys.stderr)
            raise SystemExit(2)
        if receipt:
            output = {"systemMessage": receipt}
            if context:
                output["hookSpecificOutput"] = {"hookEventName": "UserPromptSubmit", "additionalContext": context}
            print(json.dumps(output))
    else:
        parser.print_help(sys.stderr)
        raise SystemExit(2)


if __name__ == "__main__":
    main()
