## claude-code

Claude Code, wrapped so its environment/state paths agree with the
agent-vm guest (see docs/agents.md's "Shared state" section).

## codex

Codex CLI with shared agent tools, prompts, and model selectors.

## deepseek-harness

DeepSeek Harness (`dsh`) serving its browser UI, wrapped so a session runs
in the agent VM.

`ds` boots the web profile inside the guest and forwards its port back out;
`ds-native` is the unsandboxed escape hatch, exactly as with `cc` and `cx`.
Neither takes selectors: the UI is where a model, an effort level, or a
profile gets chosen, so a command line that duplicated those choices would
only be a second place for them to disagree.

`$DSH_HOME` (`~/.dsh`) is a shared state directory rather than a guest-local
volume, which is what makes `dsh plugin ... add` on either side visible to
the other. See `stateDirs.deepseek` in `libagents.nix` for the SQLite
caveat that comes with putting it on virtiofs.
