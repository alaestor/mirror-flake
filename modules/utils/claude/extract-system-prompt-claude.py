#!/usr/bin/env python3
"""Extract Claude Code's assembled system prompt verbatim, and size it.

Claude Code composes its preamble at runtime, so there is no file on disk to
read and no flag that prints it. This stands up a throwaway HTTP server, points
the CLI at it with ANTHROPIC_BASE_URL, and dumps the `system` field of the
request body before returning a 400 so nothing is billed.

The `system` field is a list of blocks:

    0  x-anthropic-billing-header: cc_version=...   (74 chars, not overridable)
    1  identity line                                (62 chars, not overridable)
    2  the entire preamble                          (overridable)

`--system-prompt-file` replaces block 2 and only block 2, which is what this
script writes out. Block 1 differs by entrypoint ("Claude Agent SDK" under
`-p`, "Claude Code, Anthropic's official CLI" interactively) but cannot be
changed either way.

Note that block 2 embeds machine-specific text: the `# Environment` section and
the trailing `gitStatus:` block reflect wherever this was run. Anything
overriding the preamble has to regenerate those itself; see the `mini` branch of
`mkClaudeWrapper` in modules/features/claude-code.nix.

# Sizing

The same request body carries the `tools` array, with every tool's name,
description and input schema. `--report` prints byte counts for both halves
instead of the preamble, which is how a patch under data/programs/claude/patches
is sized: exact, free, and right on the first try, unlike a token count read
back from a billed run.

Three inputs move those counts, and all three must be pinned to compare figures:

  * `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT`, set by `--simple/--no-simple`, which
    picks the bundle Claude Code assembles — preamble and tool descriptions
    together. There are three tiers, not two: forced off is the largest, unset
    defers to a per-model gate, and forced on is the smallest.
  * The model. With the variable unset it selects the tier outright, and even
    with it set the preamble still differs per model, though the tool
    descriptions do not.
  * `--system-prompt-file`, which replaces block 2 whatever the bundle, and
    never touches the tools.

`--compare` runs the combinations and prints the totals side by side, which is
the quickest way to see what a proposed change is actually worth.

# Limits

Gates that resolve server-side fall back to their defaults here, because the
capture runs on dummy credentials. Text the client assembles locally is exact;
a line behind a live gate may differ from what a real session sends.

Capture is driven through `claude -p`, since the interactive TUI will not submit
a turn against the dummy credentials this uses. `-p` also sends less than an
interactive session does — the git and pull-request material in the Bash
description is absent — so treat a report as a lower bound.

Usage:

    nix run .#extract-system-prompt-claude > data/programs/claude/claude-instructions-$(claude --version | cut -d' ' -f1)-full.md
    nix run .#extract-system-prompt-claude -- --report --model sonnet
    nix run .#extract-system-prompt-claude -- --compare --system-prompt-file data/programs/claude/claude-instructions-mini.md

Re-run after every Claude Code bump; the preamble changes between versions.
"""

import argparse
import http.server
import json
import os
import subprocess
import sys
import tempfile
import threading

TOOLS = "Bash,Read,Edit,Write,WebSearch"


def capture(
    tools: str,
    model: str | None = None,
    simple: bool | None = None,
    prompt_file: str | None = None,
) -> dict | None:
    """Run one throwaway turn and return the request body it would have sent."""
    captured: list[dict] = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self) -> None:
            body = self.rfile.read(int(self.headers.get("content-length", 0)))
            try:
                captured.append(json.loads(body))
            except json.JSONDecodeError:
                pass
            payload = b'{"type":"error","error":{"type":"invalid_request_error","message":"captured"}}'
            self.send_response(400)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, *args: object) -> None:
            pass

    # Port 0 lets the kernel pick, so a stale run can't collide with this one.
    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()

    # A stub prompt keeps the turn short; the preamble is sent regardless.
    with tempfile.TemporaryDirectory() as workdir:
        env = dict(
            os.environ,
            ANTHROPIC_BASE_URL=f"http://127.0.0.1:{port}",
            ANTHROPIC_API_KEY="sk-dummy",
        )
        # Inheriting this from the calling shell would silently change the
        # bundle out from under a comparison, so it is always set explicitly.
        env.pop("CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT", None)
        if simple is not None:
            env["CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT"] = "1" if simple else "0"

        command = ["claude", "-p", "ok", "--output-format", "json"]
        command += ["--tools", tools]
        if model:
            command += ["--model", model]
        if prompt_file:
            # The turn runs in a scratch directory, so a path given relative to
            # the caller's has to be resolved before the cwd changes under it.
            command += ["--system-prompt-file", os.path.abspath(prompt_file)]

        subprocess.run(
            command,
            cwd=workdir,
            env=env,
            stdin=subprocess.DEVNULL,
            capture_output=True,
        )

    server.shutdown()
    return captured[0] if captured else None


def sizes(request: dict) -> tuple[int, int]:
    """Return the (preamble, tools) byte totals of a captured request."""
    preamble = sum(len(block["text"]) for block in request.get("system", []))
    tools = sum(
        len(tool.get("name", ""))
        + len(tool.get("description", ""))
        + len(json.dumps(tool.get("input_schema", {})))
        for tool in request.get("tools", [])
    )
    return preamble, tools


def report(request: dict) -> None:
    """Print a per-tool breakdown and the preamble beside it."""
    rows = []
    for tool in request.get("tools", []):
        description = len(tool.get("description", ""))
        schema = len(json.dumps(tool.get("input_schema", {})))
        rows.append((description + schema, description, schema, tool["name"]))

    for total, description, schema, name in sorted(rows, reverse=True):
        print(f"{total:7d} = {description:6d} description + {schema:6d} schema  {name}")

    preamble, tools = sizes(request)
    for index, block in enumerate(request.get("system", [])):
        print(f"{len(block['text']):7d}   system block {index}")
    print(f"{preamble + tools:7d}   total ({preamble} preamble + {tools} tools)")


def compare(options: argparse.Namespace) -> None:
    """Print the totals for each bundle and preamble combination."""
    variants = [("verbose", False), ("default", None), ("simple", True)]
    prompts = [("built-in", None)]
    if options.system_prompt_file:
        prompts.append(("custom", options.system_prompt_file))

    print(f"{'bundle':15s} {'preamble':>9s} {'blk2':>8s} {'tools':>8s} {'total':>8s}")
    for label, simple in variants:
        for prompt_label, prompt_file in prompts:
            request = capture(options.tools, options.model, simple, prompt_file)
            if request is None:
                print(f"{label:10s} capture failed", file=sys.stderr)
                continue
            preamble, tools = sizes(request)
            block = len(request["system"][-1]["text"])
            name = label if prompt_label == "built-in" else f"{label}+custom"
            print(
                f"{name:15s} {preamble:9d} {block:8d} {tools:8d} {preamble + tools:8d}"
            )


def parse(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--tools", default=TOOLS, help=f"tool set to request (default: {TOOLS})"
    )
    parser.add_argument("--model", help="model to request the prompt for")
    parser.add_argument(
        "--system-prompt-file", help="preamble to substitute for block 2"
    )
    parser.add_argument(
        "--report",
        action="store_true",
        help="print byte counts instead of the preamble",
    )
    parser.add_argument(
        "--compare",
        action="store_true",
        help="print totals for each bundle and preamble combination",
    )
    simple = parser.add_mutually_exclusive_group()
    simple.add_argument(
        "--simple",
        dest="simple",
        action="store_true",
        default=None,
        help="force the terse bundle for any model",
    )
    simple.add_argument(
        "--no-simple",
        dest="simple",
        action="store_false",
        help="force the verbose bundle for any model",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    options = parse(argv)

    if options.compare:
        compare(options)
        return 0

    request = capture(
        options.tools, options.model, options.simple, options.system_prompt_file
    )
    if request is None:
        print("no request captured; is `claude` on PATH?", file=sys.stderr)
        return 1

    if options.report:
        print(f"model: {request.get('model')}", file=sys.stderr)
        report(request)
        return 0

    blocks = request["system"]
    print(f"captured {len(blocks)} system blocks:", file=sys.stderr)
    for index, block in enumerate(blocks):
        print(f"  {index}: {len(block['text'])} chars", file=sys.stderr)

    sys.stdout.write(blocks[-1]["text"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
