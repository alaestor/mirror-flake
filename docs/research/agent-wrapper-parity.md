# Claude and Codex wrapper parity

Both wrappers provide model and effort selection, approval-mode selectors,
shared shell tools and RTK guidance, shared skills, a project context file,
the context guard, Tokview observation, and VM isolation with an explicit
native entry point. Neither starts Serena or compresses tool output.

## Differences worth deciding separately

| Concern | Claude | Codex |
|---|---|---|
| Prompt depth | `mini` replaces the system prompt; `full` preserves the vendor prompt. | `small` selects a model instruction file; `full` omits the wrapper override, but the managed config still supplies its default file. It is not yet a true stock-prompt mode. |
| Tool catalogue | A restricted default set; `alltools`, `skills`, and `lean`/`verbose` refine it. | Vendor catalogue controlled mainly by feature settings, without equivalent wrapper selectors. |
| Project instructions | Injects only the project root's `AGENTS.md`; `noagentsmd` skips it. | Uses Codex's native instruction discovery, including nested files. |
| Memory | Native project memory and an explicit memory-directory reminder. | Vendor memory facilities, without the same wrapper reminder. Headroom's optional memory and graph modes are gone. |
| Extended context | `1m` selects native model suffixes and scales the guard's window. | The guard reads the model's window from its transcript; no equivalent selector. |
| MCP | Starts with an explicit empty server set; native tool search remains selectable. | No injected server set; normal Codex configuration and discovery remain available. |
| Compaction hook | Blocks automatic compaction only. | The guard receives all `PreCompact` events and currently blocks manual compaction too. |
| Skills | The `Skill` tool and its catalogue are opt-in; slash skills remain available. | Managed skills are available through vendor-native discovery, with some skills disabled in settings. |

The first follow-up should be to define what `full` guarantees, then fix the
Codex implementation to meet it. Manual compaction behavior should also agree.
Tool and skill switches can share intent without pretending the vendors expose
identical controls. Context-guard opt-out remains deferred.

Tokview's native and VM databases are separate for both harnesses. This is an
isolation constraint, not a Claude/Codex discrepancy.
