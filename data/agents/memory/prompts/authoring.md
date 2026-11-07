# Admit knowledge selectively

Ask whether forgetting this would cause repeated investigation, a recurring
mistake, or a materially worse decision. Record the surprising constraint,
failed approach, or explanation, with enough evidence to verify it later.
Do not copy repository inventories, ordinary documentation, generic advice,
conversation summaries, or speculation into memory. Memory is disposable; put
critical invariants and authoritative guidance in version-controlled documentation
or instructions, not solely in this store.

Search both scopes before adding anything. Refine an existing article when it
already owns the subject. Prefer project scope unless the lesson genuinely
applies across projects. Use repository-relative paths for project files.

Choose a short lower-kebab-case name, a trigger explaining when to read, and a
concise Markdown article. The name identifies the memory; no display title is
needed. State the claim, why it matters, evidence, and limits. Omit headings
that add no information. A useful memory often fits in a few paragraphs.

Write directly through stdin, with a quoted heredoc delimiter:

```sh
memory add project:example --trigger '...' --file - <<'EOF'
A concise claim, its evidence, and the practical consequence.
EOF
```

`--file draft.md` also accepts an existing file. For edits, read first, then
supply `--expect <revision>` and `--file -` with the replacement article.
Global options such as `--json` and `--project-root` precede the command.
A blocked admission preserves a draft and leaves accepted knowledge unchanged.
Do not split articles or raise budgets merely to evade admission limits.

Each memory owns a directory containing `README.md` and CLI-managed
`metadata.json`. `add` and `show` expose that directory; `memory path <id>` prints
its path without counting a read. Put optional supporting notes or scripts there
directly. README edits through the CLI preserve those files. Supporting files
count toward the content budget; do not evade quotas by moving prose into them.

Use `verify.sh` only as an optional entry-point convention. Multiple checks and
relative-path helpers are fine. Explain prerequisites and what each check can
establish in the README. Follow `memory explain verification` for safe execution
and partial results. The CLI never runs attached code. Keep project regression
tests in the project, not in memory.
