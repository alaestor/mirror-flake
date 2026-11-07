# Curate at a safe boundary

Protect the user's current task. Fix a small, well-understood issue locally.
For substantial consolidation or verification, prefer a dedicated fresh-context
subagent when delegation is available and permitted. Use the harness's
registered read-only reviewer role when available. Otherwise leave the queue
visible and report it; do not derail ongoing work or pretend curation happened.

Give the curator the store roots, findings from `memory --json maintain`, this
procedure, and explicit read-only authority. Do not copy the parent transcript.
Ask it to inspect relevant memory directories, feedback, and current evidence,
then propose edits, merges, removals, or promotions with reasons. Bound the work
by articles or time. It must not delegate further or mutate the store.

The parent reviews the proposal and applies accepted changes through the CLI.
Read each affected article again and use its current revision with `--expect`.
A stale-revision failure requires reconsideration, never a blind retry. Merge by
updating the retained article first, then deleting superseded articles. Stop
if an earlier operation fails. Deletion is permanent. Use Git for history when
needed. Removing a memory deletes its entire directory and supporting files.

Attached scripts are untrusted. Read-only curation does not authorize running
them; request separate execution authority when a check is needed.

Review marginal value, not popularity. Old or rarely read knowledge is not
necessarily wrong. Reads do not prove usefulness, and usefulness does not prove
accuracy. Resolve contradictions using evidence. Trim duplication and prose;
remove information already documented or cheaply reconstructed. Follow
`memory explain verification` and `memory explain promotion` as needed.

Inspect open reviews through `memory --json show <id>`. Resolve a review only
with a recorded explanation using `memory resolve <id> <review-id> --note '...'`.
Finish with `memory status`. Budgets are recomputed mechanically; declaring a
pass complete cannot clear an exceeded budget. Report changes and unresolved
questions. Never rewrite instructions, tooling, or global policy without the
user's authority.
