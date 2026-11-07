# Agent memory

Memory preserves discoveries that are expensive or error-prone to reconstruct.
It is not a transcript, repository inventory, or substitute for documentation.
An article earns its place by preventing repeated work or mistakes. Repeated
lessons should eventually become documentation or enforced tooling, making the
article unnecessary.

## Ownership and integration

The implementation lives under `data/agents/memory/`. It uses Python's standard
library, ordinary writable directories, and no model API. Nix packages it in
`modules/mechanisms/libagents/memory.nix` as `packages.<system>.agent-memory`.
The shared harness library supplies the executable and session instructions to
both harnesses. See [Coding agents](agents.md) for wrapper ownership.

The CLI never starts an agent. It measures conditions and renders instructions;
the running agent supplies editorial judgment. Substantial curation should use
a fresh-context, read-only subagent when available and permitted. The parent
reviews proposals and applies accepted changes. Lack of delegation support does
not justify interrupting the user's task with a store-wide review.

Project articles live under `<project>/.agents/memory/`; global articles live
under `~/.agents/memory/`. Projects choose whether to track their store in Git.
The harness layer contributes the global directory as shared VM state. This
requires the normal system deployment and a VM restart when introducing the
share. Project stores travel with their existing project shares. The VM knows
nothing about memory semantics.

Identifiers always include scope, for example `project:compiler-cache` and
`global:compiler-cache`. Discovery shows both; there is no implicit shadowing.
Use a short lower-kebab-case name. There is no separate display title; discovery
shows the scoped identifier followed by its trigger.
An agent must investigate contradictions rather than assuming one scope wins.
Project roots default to Git's top level. Outside Git, use `--project-root` or
`--scope global`. `--global-root` supports isolated stores and tests.

## Editing the instructions

All substantive memory instructions are Markdown under
[`data/agents/memory/prompts/`](../data/agents/memory/prompts/).
Their names match their jobs:

- `session-start.md` provides the always-present discovery and trust rules.
- `authoring.md` controls admission and concise writing.
- `feedback.md`, `verification.md`, and `promotion.md` separate usage, evidence,
  and proposed changes to documentation or tooling.
- `curation.md` defines safe scheduling, fresh-context delegation, and review.
- `warnings/` contains the response to each mechanical warning condition.

The memory skill points agents to these prompts rather than duplicating them.
Use `memory explain curation` or `memory explain warnings/budget-exceeded` to
inspect the installed text. Source-only preview needs no Nix evaluation:

```sh
python3 data/agents/memory/src/memory.py explain authoring
```

Prompt edits require rebuilding and activating Home Manager and starting a new
session, just like other packaged harness tools. Runtime memories remain
writable data, never store-backed configuration. `AGENT_MEMORY_PROMPTS` can
select another prompt directory when running the Python source directly.

## Operations

Global flags precede the command. `--json` gives structured output; diagnostics
go to stderr. Human-readable `session` output includes unsuppressed warnings
so wrapper command substitution delivers them to the model. Other operations
leave their data output separate from warnings.

```sh
memory index
memory search 'cache ownership'
memory show project:compiler-cache
memory path project:compiler-cache
memory add project:compiler-cache \
  --trigger 'When a build cache rejects writes' --file - <<'EOF'
Record the surprising constraint, evidence, and practical workaround here.
EOF
memory edit project:compiler-cache --expect <revision> --file revised.md
memory feedback project:compiler-cache useful
```

`show` counts reads, but neither discovery nor search does. Reads never imply
usefulness. Feedback counters distinguish useful, relevant-unused, and off-base
retrieval. Off-base feedback or a textual comment opens an editorial review.
`memory --json show <id>` includes review IDs and revision-specific evidence.
Use `resolve <id> <review-id> --note 'explanation'` after addressing a review.
Counters persist; review details are bounded. A full queue of unresolved reviews
refuses new reviews instead of silently discarding them.

`--file article.md` reads an existing file; `--file -` reads stdin and supports
heredocs, as shown above.

`add`, `edit`, and `show` expose the memory directory in their output.
`memory path <id>` prints that path without counting a read. JSON `show` includes
both `path` and `content`; JSON `path` is a path string. Search examines the identifier,
trigger, and README, not arbitrary attachments.

For human oversight:

```sh
memory status
memory usage
memory maintain
memory promotions
```

`status` reports per-scope budgets and findings. `usage` exposes retrieval and
feedback counts. `maintain` adds the curation procedure; its JSON form contains
findings only. A maintenance pass cannot acknowledge away a budget violation.
Warnings repeat after a configurable cooldown or when the findings change.
Resolve promotion proposals before deleting their source article.

`propose <id> --proposal 'change and owner' --evidence 'recurrence'` records a
promotion candidate. It is not permission to change the harness or policy.
`promotion-close <id> --note 'outcome'` records its resolution.

## Budgets and publication

Edit [`data/agents/memory/settings.json`](../data/agents/memory/settings.json)
in this flake to change budgets and reminder timing. Rebuild and activate Home
Manager to deploy them. Both scopes use the same settings, with separate usage
accounting. There are no per-project or per-store overrides yet.

The policy file defines:

| Setting | Meaning |
|---|---|
| `index_bytes` | Admission budget for rendered index lines |
| `content_bytes` | Admission budget for READMEs and supporting files |
| `articles` | Admission budget for the number of articles |
| `article_bytes` | Warning threshold for an individual article |
| `reminder_hours` | Cooldown for unchanged maintenance findings |

Byte counts are exact UTF-8 sizes, not claims about
a model's tokenizer. The index budget counts the rendered identifier and
trigger lines. Both scopes have independent budgets, so the combined catalog
can reach their sum. Discovery never silently truncates an over-budget store.

At 80 percent of an admission budget, the CLI requests curation. New admissions
and edits that worsen any exceeded admission budget fail. Reads,
removal, and edits that do not worsen exceeded budgets remain possible.
Article size and likely checkout-specific absolute paths produce warnings,
not hard failures. Some absolute paths are essential evidence. Direct writes to
supporting files are agent-managed, so the CLI cannot prevent them exceeding a
budget; it reports the excess on subsequent operations and refuses further CLI
growth. Content accounting excludes CLI-managed `metadata.json` and does not
follow attached symlinks. The large-article warning concerns the main README.

A failed admission preserves the submitted trigger and body in a private
JSON draft under the system temporary directory and prints its path. Accepted
knowledge remains unchanged. Drafts are not memories and are not indexed;
remove them after recovering the work. There is no automatic budget increase.

The explicit `AGENT_MEMORY_CONFIG` environment variable selects another policy
file for standalone use and isolated tests. The packaged CLI supplies its
flake-owned default; it never searches a project for configuration.

## Memory directories

Each memory owns a directory under the store's `articles/` directory:

```text
articles/compiler-cache/
  README.md
  metadata.json
  verify.sh              # Optional conventional entry point
  checks/                # Optional helpers or independent checks
  supporting-notes.md    # Optional documentation
```

`README.md` is the main article. `metadata.json` holds its trigger, current
revision identifier, and usage feedback. There is no separate index to maintain.
The store's `.notice.json` records the warning cooldown. Policy comes from the
packaged settings file, not the mutable store.

Authors manage supporting files directly through the exposed path. README edits
through the CLI preserve them. There is no attachment manifest, verifier
registration, or automatic execution. Supporting scripts are untrusted, just
like commands copied into a memory. Their presence is not permission to run them.

`verify.sh` is an optional naming convention. A memory can have multiple scripts,
additional documentation, and helpers invoked by relative path. Inspect a script
before explicitly running it within the existing permissions and isolation,
usually from the memory directory. Document prerequisites and what each check
establishes. These scripts test remembered assumptions; they do not replace
project tests. Do not write ceremonial checks for unverifiable claims.

Interpret results per claim rather than marking the whole memory verified.
A failure might indicate a changed environment, a missing prerequisite, a broken
check, or obsolete advice. Describe mixed results in ordinary prose and use
`feedback <id> off-base --comment '...'` to open a review when needed. Neither a
failure nor a passing script automatically changes or deletes an article. There
is no `confirm` or `verify` command, confirmation timestamp, or age-based review.
The editable `verification.md` prompt describes this agent-led procedure.

## Publication and deletion

CLI operations use a store lock and atomic individual file writes. README edits
require the expected revision to avoid overwriting concurrent CLI work. This is
not a transaction across a directory: an interrupted write can leave a mismatched
README and metadata. A checksum detects that write-integrity issue. Discard and
recreate the memory, or restore it through Git if the store is tracked. This
checksum says nothing about whether a claim is true. Use the CLI for README and
metadata changes; supporting files remain ordinary agent-authored files outside
these revision checks.

`remove <id> --expect <revision>` permanently deletes the selected directory and
all its contents, without following attached symlinks. There are no archives,
snapshots, restore commands, or internal revision history. Memory is disposable.
Anything important enough to require durable recovery belongs in version-controlled
documentation, instructions, or tooling. Project stores may also be tracked in
Git, but the CLI does not manage commits.

Each article retains at most twenty review and closed-proposal events. Resolved
entries can make room for new feedback; unresolved reviews cannot be silently
evicted. Store paths, memory directories, README files, and metadata files must
not be symlinks. Supporting symlinks are neither traversed for accounting nor
followed during deletion. The CLI is not a security boundary against another
process with the same filesystem authority.

The earlier flat Markdown/JSON layout, TOML store, and `project-memory` command
are not supported or migrated. Existing files are left untouched and are not
indexed. Handoffs remain separate under `.agents/session/`.

## Validation

The focused check runs the same public CLI tests against the packaged tool:

```sh
nix build .#checks.x86_64-linux.agent-memory --no-link
nix build .#checks.x86_64-linux.agent-wrappers --no-link
```

For a source-only run, execute
`python3 data/agents/memory/tests/test_memory.py`. Tests use isolated temporary
stores, not personal or repository memory.
