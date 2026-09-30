# Prompt directives

Directives run before the agent receives a user's turn. They are explicit
commands, not model-invocable skills: the user writes `^^name` or
`^^{ name raw arguments }` in the prompt. The bounded form passes everything
after the name as one argument, including spaces and newlines. `\^^` escapes
the prefix. The parser also recognizes directive syntax inside quotes and code
blocks, so escape examples that must remain literal.

The original prompt still reaches the agent. Directive stdout is separate
context, wrapped with start/end markers and a note identifying its source.
For the harness design and isolation boundary, see [Coding agents and their
isolation](../../../docs/agents.md).

## Add a directive

- Put instruction-only text in `macro/<name>.md`. Its contents become model
  context. Macros take no arguments.
- Put a packaged program in `script/<name>.nix`. Export `description` and
  either `command` or `alias`. The command receives the raw argument string as
  its only argument and runs in the prompt's working directory. Write model
  context to stdout, a user-facing note or error to stderr, and return nonzero
  on failure. A successful script may write nothing to stdout.
- Keep helpers outside `macro/` and `script/`. The loader discovers `.md` and
  `.nix` files recursively in those trees, but uses each file's basename as
  its global directive name. Duplicate names fail evaluation. The script
  catalogue includes each definition's description; macros have no displayed
  description.

`default.nix` builds the catalogue; `../directives.py` parses prompts, runs
commands, and adapts their results for Claude and Codex. The harness package
passes the catalogue path to scripts as `AGENT_DIRECTIVES_CATALOGUE`. Use that
only when a script needs to inspect the catalogue, as `list` does.

## Output and turn control

On success, the resolver combines ordinary directive stdout into one context
injection. It sends stderr to the user, or a short completion receipt when
stderr is empty. It never copies ordinary stdout into that receipt. A script
with `displayOnly = true` instead writes its user-facing result to stderr;
the resolver shows it and blocks the turn without injecting stdout. `list`
uses this path. Invoke `^^list` by itself: earlier directives in the same
prompt can still run before it.

The resolver checks all names before running any command. An unknown name
blocks the whole prompt. A failed or timed-out command blocks the prompt and
skips later directives, but earlier side effects remain. Hook calls have a
30-second command timeout. Every invocation records metadata, never raw
arguments or output, in the directive event log. If logging fails, the command
does not run.

## Check a change

Run `agent-directives list --json` to inspect the packaged catalogue, or
`agent-directives run <name> 'raw arguments'` to call one directive in the
current directory. Terminal `run` preserves the command's stdout, stderr, and
exit status; it does not apply hook turn control. Test the hook behavior with
`nix build .#checks.x86_64-linux.agent-directives --no-link`. New files must
be staged before Git-backed flake evaluation can see them. Do not run
`mkflakedocs` to update this guide: it regenerates subdirectory READMEs from
Nix docstrings and can overwrite hand-written text.
