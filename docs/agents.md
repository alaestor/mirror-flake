# Coding agents and their isolation

A coding-agent harness is a wrapper around a vendor CLI that decides which
prompt, tools, and state the agent gets, and where the session runs. Sessions
run inside a shared NixOS microVM rather than on the host, so an agent acting
on a bad instruction can damage only what the guest was given.

The central safety property is:

> A wrapped session can reach only the trees shared into the guest at boot, and
> the only way to run a harness outside that boundary is to invoke its
> `<name>-native` package explicitly.

Isolation is a property of the wrapper, not of the vendor CLI. Nothing in the
guest is trusted to restrict itself.

## Layers and ownership

| Layer | Export | Owns |
|---|---|---|
| Harness library | `flake.lib.agents` | Prompt fragments and resolution, tool lists, directives, selector-loop and wrapper factories, and per-harness VM contributions. |
| Harness feature | `flake.modules.homeManager.<harness>` | One CLI: its packages, prompt depths, settings, and the `sandbox` seam that hands a session to the isolation boundary. |
| VM layer | `flake.lib.agents.mkAgentVm` | A guest NixOS configuration: shares, guest identity, sshd, and the guest half of each channel. |
| Host mechanism | `flake.modules.nixos.agent-vm` | The single VM instance, the host half of each channel, session lifecycle, and the `agent-vm-session` entry point. |
| Host | `host.<name>` and its fragments | Which harnesses are attached, which trees the agent may work on, and platform sizing. |

The harness features themselves live in `modules/features/slop/`. Everything
else lives in `modules/mechanisms/libagents/`.
It is a mechanism, not a feature: no host asks for "a VM manager for coding
agents", it gains one as a consequence of attaching a harness
([Module ownership](modules.md), §Reusable modules).

### The layering rule

The VM layer must never name a harness fact: not a config directory, not a
model, not a prompt. It receives opaque lists (`projectRoots`, `stateDirs`),
opaque `name = value` pairs (`guestEnvironment`), and opaque `/etc`-relative
paths (`guestEtc`), and it is the harness layer's job to know what they mean.
Conversely the harness library must never mention vsock, virtiofs, or systemd
units.

The seam between them is deliberately thin: a harness feature's `sandbox`
function hands its own `-native` package to the host's session entry point. That
one call is the only place a harness knows isolation exists, so replacing the
isolation technology is a change to that function and nothing else.

### One owner for the instance

Several harnesses share one guest, so exactly one module declares it
([Module ownership](modules.md), §Shared instances). Harnesses and hosts
contribute the facts that are theirs, the trees to share and the state to
preserve, and may raise `enable` only as a default. Identity and platform
parameters (guest name, user, uid, vCPUs, memory, forwarded port) belong to the
mechanism as defaults and to the host as policy.

VM state is a harness fact, contributed by the host that attaches the harness.
A standalone Home Manager environment is not evaluated during a NixOS rebuild,
so the harness module cannot contribute it directly;
`flake.lib.agents.vmContributionsFor` resolves the selected harness records into
the VM's shared directories, guest-local directories, and environment.

The allowed work trees follow the same single-source rule. Harness wrappers use
`flake.lib.agents.sandboxWritableRootsFor` for their admission check, and the
host uses that list as the VM's fixed `projectRoots` shares.

## Session configuration

The wrappers configure prompts and tools directly in the vendor CLI. They do
not rewrite API requests or tool output to compress context. RTK is available
for selected noisy commands; exact source, diffs, and machine-readable output
must remain unfiltered.

Claude starts with an explicit MCP configuration rather than inheriting stale
registrations from its auth-bearing state. Its native tool-search and extended
context settings belong to the Claude wrapper, not to a proxy.

## Token observability

The Tokview feature owns one on-demand user service per environment. Both
Claude and Codex send provider traffic through its loopback proxy and wait for
readiness before launching. Proxy failure stops launch rather than silently
losing observations. Codex receives its endpoint through invocation-time
configuration; do not use `tokview wrap codex`, which rewrites the immutable
Home Manager config.

The feature owns the CLI, ports, and managed configuration. Harnesses import it
and enable it as a default; setting `services.tokview.enable = false` restores
direct provider connections. Prompt and response capture are disabled by
default. This replaces compression with observation: prompts, responses, and
tool results are not compressed. Provider routing remains the proxy's concern.

Tokview uses SQLite WAL, so `.tokview` is guest-local persistent state. Native
and VM sessions intentionally have separate databases. Use
`tokview show --watch` for native sessions and `tokview-guest show --watch` from
a shared work tree for VM sessions. The guest CLI uses the same isolation
entry point as the agent wrappers; it does not mount or copy the database onto
the host. The host attaching the harnesses contributes Tokview's local-state
record alongside theirs.

## Explicit directives

Directives are named programs invoked by the user's current prompt. `^^name`
invokes one without arguments; `^^{ name raw arguments }` passes the text after
the name as one argument, including spaces and newlines. A backslash before
`^^` makes a literal example. The parser does not exempt quotes or code blocks.
Multiple directives run in prompt order before the model sees the turn. They
may change files, and normally their stdout becomes one combined context injection.
The original prompt remains visible, so this is not textual expansion. A
directive can produce no stdout. On success, stderr is its user-facing note;
if stderr is empty, the resolver shows a short completion receipt. It does not
copy stdout into the receipt. The resolver checks every name before running
any command. An unknown name blocks the prompt without running any directives.
A command failure or timeout blocks the prompt and skips later directives;
earlier side effects are not rolled back.
`^^list` shows the available names to the user and blocks the turn, so the
agent does not answer a catalogue request. Script entries include descriptions;
macro entries show names only. Put `^^list` alone to avoid running earlier
directives before it.

Every invocation appends metadata to
`$XDG_STATE_HOME/agent-directives/events.jsonl`, or
`~/.local/state/agent-directives/events.jsonl` when `XDG_STATE_HOME` is unset.
The JSONL records time, source, directive name, working directory, outcome,
and duration. Unknown names are recorded as `<unknown>`. It does not store raw
arguments, stdout, or stderr. New log files have mode `0600`. The runner
records a start before executing a command and an outcome afterward; if it
cannot write the log, it blocks rather than run an unlogged command. The VM
shares this state directory with native sessions, so guest restarts do not
discard the log.

The catalogue is discovered recursively from `data/agents/directives/macro/`
and `data/agents/directives/script/`. A Markdown file under `macro/` injects
its text and rejects arguments; a Nix file under `script/` returns a definition
with a description and either a packaged command or an alias. Each filename
becomes a directive name, regardless of its subdirectory. The loader in
`data/agents/directives/default.nix` rejects duplicate basenames across both
trees before constructing the catalogue. See the
[directive authoring guide](../data/agents/directives/README.md) for local
conventions. Put supporting files outside these two trees so they are not
accidentally registered. The command
receives the raw argument string as its only argument and runs in the prompt's
working directory. It writes optional model context to stdout and a user note
or error to stderr. It returns nonzero on failure. Hook and expansion calls run
commands directly, without a shell or word splitting, with a 30-second timeout.
The resolver passes the catalogue path to scripts in
`AGENT_DIRECTIVES_CATALOGUE`. A script marked `displayOnly` writes user-facing
text to stderr. The resolver shows that text and blocks the turn after the
script succeeds; it does not inject stdout from that script.
Terminal calls have no hook timeout. The resolver exposes
`agent-directives list --json` for clients that need a catalogue and
`agent-directives expand --json` for callers outside the hook protocol. Failed
expansion returns `ok = false` and exits with status 2. Hook failures likewise
exit 2 with the blocking reason on stderr, which both harnesses use to reject
the prompt. The same package works at a terminal:
`agent-directives run pickup` writes the command's raw stdout and stderr and
returns its exit status. Pass optional raw arguments as one quoted shell
argument, for example
`agent-directives run example 'two words'`.

Procedural directives such as `handoff` and `what` inject instructions
rather than performing the work themselves. The agent must still write the
handoff file or compose the revised answer.
`pickup` differs: it reads the latest handoff and injects its contents. These
workflows need no vendor skill. `grill` injects the interview procedure;
`grill-with-docs` composes it with the `domain-modeling` macro, which includes
its document formats in one file. Both live under `data/agents/directives/macro/`.
Reading a `CONTEXT.md` for vocabulary does not invoke domain modeling; use its
directive when deliberately changing the domain model or recording decisions.
These composed directives do not call a vendor Skill tool. The two
`subagents-*` procedures are also explicit directives, not skills.
Deprecated Nix skills have no directive replacement. The unused `speaking`
skill is absent because these harnesses do not provide a Speak tool.

Both harnesses register six model-invocable skills: `docs`, `unslop`,
`general-testing`,
`git-conventional-commits`, `git-howto-change-commit-message-history`, and
`nix-flake-component-flake-parts`. Their source files remain under
`data/agents/skills/`; `flake.lib.agents.skills` selects only these six.
They are not directive names. The Codex guest wrapper recreates their links
on launch and removes links left by older generations without replacing
user-owned skills.

Both harnesses call the same resolver at `UserPromptSubmit`. Claude registers
it through Home Manager; Codex registers it in managed system configuration,
where a store-backed hook can run without a per-generation trust prompt. The
Codex hook is a fixed shim, not a path to one directive generation. `cx-native`
exports the current Home Manager package path before launching Codex, including
inside the VM. Direct native `codex` may fall back to the host's Home Manager
profile. The shim requires the executable to resolve inside `/nix/store` and
fails if it cannot find one. It never follows a guest-writable shared pointer
back to the host. Restart an already running VM for the initial shim deployment.
After that, directive edits need only a Home Manager activation and a new Codex
session; the running VM does not need a restart.

The hook adapter sends stderr or its fallback receipt as `systemMessage` and
ordinary directive stdout as `additionalContext`; the directive scripts need
no harness-specific protocol. The successful `pickup` note contains an
absolute path for copying.
The resolver wraps injected output in `BEGIN`/`END EXPLICIT DIRECTIVE OUTPUT`
markers and a short note identifying it as output from the current prompt's
directives. The original prompt stays separate. Hook UIs may or may not turn
the `pickup` path into a clickable link. Codex accepts
`systemMessage`, but `codex exec` does not print it in normal or JSON output;
interactive Codex displays it as a hook line.
Codex's handler raises its context limit to 200 KB; the default truncates
ordinary directive output. A wrapped session executes commands inside the
shared VM. An explicitly native session does not gain that isolation, so only
trusted Nix-packaged programs belong in the catalogue. Vendor skills do not
provide directive dispatch.

## Opt-in shared memory

Project notes use `.agents/memory/<name>.toml` at the repository root. The
`project-memory` command works in either harness, with or without Cognee. Each
file has a short `trigger` describing when to open it and a Markdown `content`
stored as a multiline TOML literal string. At session start the wrappers add
only filenames and triggers to the prompt, capped at 30 entries and 200
characters per trigger. Agents read relevant content with
`project-memory read <name>`; the command returns content alone. Use
`project-memory new|edit|delete <name>` to maintain files. The command uses
`$EDITOR` and validates TOML before replacing an existing memory. It does not
maintain an index. Projects decide whether to track `.agents/memory/` in Git;
this repository ignores dot-directories by default. Keep secrets and session
handoffs out of project memory. Claude's own auto-memory is disabled in its
Home Manager settings, so it cannot silently create a competing store.

Cognee remains a separate opt-in store:

`mem` or `memory`, before `--`, enables Cognee for that invocation of `cc`,
`cx`, or their `-native` counterparts. Without the selector, no memory service
is started and no Cognee tools are enabled. Launch fails if the configured
host-local LLM or memory service is unavailable.

Cognee runs as an on-demand host user service. Its SQLite, vector and graph
databases and model caches stay on the host; none are added to guest shares.
The MCP adapter exposes text `remember` and `recall`, plus single-item
`forget` by `data_id`; it does not expose arbitrary host file ingestion or
dataset-wide deletion. Forget requires an explicit project or global scope
and permanently removes that item. Both harnesses use the same store. Remember defaults to the
current project's scope, with global scope available for cross-project facts;
recall searches both by default. Project identity is the canonical repository
root, or the working directory outside a repository. These scopes organize
memory, not authorization between mutually untrusted sessions.

Native sessions connect directly to the host loopback endpoint. Wrapped
sessions prepare the host service before entering isolation, then use a
loopback-only reverse SSH forward on a per-session guest port. Parallel
sessions do not share a forward's lifecycle, and ordinary sessions add no
memory forward. The generic isolation entry point owns forwarding; the
memory feature owns the endpoint and storage.

The host user configuration selects the LLM endpoint. The service uses the
first model advertised by `/models` when it starts; an opted-in launch restarts
it if that model changes. No real API credential is required by this local
setup. Embeddings run locally through FastEmbed and download their model on
first use. Memory tools are available
to the agent, not an automatic transcript logger; never store secrets.

Stop the host service with `systemctl --user stop cognee-memory.service`.
The next opted-in launch starts it again. Inspect failures with
`journalctl --user -u cognee-memory.service`.

## The context guard

Normal vendor compaction is the default. The `guard` selector opts a session
into shared context protection: `cc guard` or `cx guard`, including their native
counterparts. Use `-- guard` to pass the word to the vendor CLI instead.

The opt-in guard (`flake.lib.agents.contextGuard`) watches the session's own
transcript and, past a threshold below the point the harness would compact on
its own, asks the agent to write a handoff and then blocks further work once
it exists. Claude's
wrapper delays proactive compaction only when opted in. Its registered hooks
are otherwise inert, using an explicitly reset process-local flag. Codex keeps
the four guard handlers disabled in user configuration and overrides only
their enablement through session flags. This avoids sharing daemon environment
state and leaves unrelated hooks alone. Resuming without `guard` disables the
guard for that invocation; opt-in is not persisted to future launches.

The guard is a harness fact but lives in the library rather than in a harness
feature, because the two sides register it from different module classes: Claude
Code takes hooks from Home Manager settings, while Codex trusts hooks
declared in the *system* config layer without interactive trust. The guard must
run in both native and wrapped sessions. It selects behaviour from `argv[1]`, and
only two things vary — how the transcript reports live context, and which JSON
verb halts a turn. Adding a harness means adding an entry to that table, not
forking the script.

Handoffs land in `.agents/session/<YYYYMMDDTHHmmss>-<topic>.md` under the
directory the session started in, kept distinct from a `handoff.md` written
deliberately by the handoff skill: these are recoverables produced under duress.
The agent chooses the topic slug, so the guard detects completion by mtime
against the session's own start rather than by a path it computed.

The same script also renders Claude Code's status line, invoked with
`statusline` instead of a harness name. It is not a hook: the status-line
payload reports the live context window, so it leads the transcript the hook
path reads. When guarded, it counts down to the handoff threshold; otherwise
it shows ordinary context remaining. Keeping it in the guard is deliberate —
an indicator that predicts an event must share the constant that triggers it,
or the two drift apart.

It also reports the plan's 5-hour and weekly quota windows, which the same
payload carries. Those are absent for API-key, Bedrock, and Vertex auth and
until a response has carried the quota headers, so the renderer omits whatever
is missing rather than assuming a shape.

A harness whose hooks need system-level registration cannot be served by the
harness feature alone, since the guest runs no Home Manager and a
standalone Home Manager attachment is not evaluated during a `nixos-rebuild`.
The host that attaches the harness contributes the file through `guestEtc`,
exactly as it already contributes `stateDirs`. For native Codex sessions, the
host also installs the same file through `environment.etc`. User-level Codex
hooks require persisted trust, which a Nix-managed user config cannot record.

## Shares and state

Every share is mounted at the **identical host path**. Path identity is what
makes a store path, a `result` symlink, a `gcroot`, or an error message mean the
same thing on both sides, and it is why a session can be handed a host-built
wrapper by store path and simply execute it.

Three contribution points, kept separate because they answer different questions:

- `projectRoots`: what the agent may work on. Fixed at guest boot; a session
  outside them is refused rather than the boundary widening to fit.
- `stateDirs`: what must outlive the guest: sessions, memories, caches,
  credentials.
- `localStateDirs`: durable state that must remain on a guest-local filesystem,
  such as SQLite WAL databases that must not be placed on virtiofs.

Anything neither shared nor backed by a local-state volume is ephemeral. The
guest's root filesystem is tmpfs, so a home directory, shell history, or
configuration file that neither mechanism covers is gone at shutdown.

Codex's `~/.codex` is a local-state volume. The sandbox wrapper recreates its
declarative Home Manager links on entry, while sessions, credentials, and
SQLite databases remain together on that volume. Host-native Codex keeps using
the host's ordinary `~/.codex`; the two stores are intentionally independent.

The ownership rule: the guest runs no Home Manager. Home Manager symlinks at
file granularity, so a second generation over a shared directory renames the
first one's files out of the way. The host's generation is the sole manager of
managed files; the guest gets packages, wrappers, and live state only.

The consequence is that a *rendered* configuration file the host keeps under
`$HOME` does not exist in the guest at all, even though the store path holding
it does. Where a tool supports it, point the tool at that store path from the
harness wrapper rather than adding a share: git identity travels as
`GIT_CONFIG_GLOBAL`, and without it the guest has no `user.email` and no
signing configuration. Such a value is a function of the *home* configuration,
which the VM layer cannot see, so it cannot travel through `guestEnvironment`
and must be exported by each wrapper. It therefore belongs in a shared fragment
in `flake.lib.agents` (`gitEnvironmentText`) and not in one harness, or the
next harness silently ships without it.

## Channels

Host-side channel units remain in `vm-host.nix`: they refine the same
`agent-vm` option schema, user attachment, and VM lifecycle as the rest of the
host mechanism. Splitting them would create an internal NixOS module export
without an independent consumer. Only reusable channel constants and the proxy
service constructor live in `vm-channels.nix`.

A channel gives the guest one host capability without giving it the host. Each
is a unix socket in the guest, socket-activated per connection and proxied over
`AF_VSOCK` to a host listener that connects to the real socket. Guest and host
halves are separate modules; the constants they must agree on (host CID, ports,
the CID derivation) live in one place.

Channels are not authenticated: any guest with vsock access can dial them. The
security of a channel is therefore a property of what sits behind it, and every
channel must be safe to expose to an untrusted guest:

- The nix daemon channel runs as an account that is deliberately *not* a trusted
  user, so the guest may build and add store paths but cannot tell the daemon
  what content to trust. The guest's own daemon is disabled rather than left
  running, because two daemons over one store corrupt it, and a silent local
  fallback would hide a broken channel behind a slow build.
- The gpg-agent channel forwards the *restricted* agent socket, which signs and
  decrypts but refuses to export a key. Private key material never leaves the
  host, and every operation still requires whatever the host's agent demands.
  Because the socket is per-session, the channel works only while the host user
  has a session, which is honest, since a signature needs the human anyway.

Ports are host-wide and must not be renumbered once a guest exists in the wild;
CIDs are per-VM and derived from the guest name so no registry is needed.

## Lifecycle

The guest does not run at boot. `agent-vm-session` is the single entry point: it
starts the VM unit if needed, waits for sshd, and runs the requested command
inside a transient systemd scope. Reference counting falls out of that: a
scope's lifetime is its cgroup's, so it ends when the session process does, with
no release step to be skipped or killed. A linger hold keeps the guest up for a
grace period so consecutive sessions do not reboot it.

The host key the guest presents is pinned in a scratch `known_hosts` computed
from the same source the guest uses, so no session ever prompts for or writes a
TOFU entry.

## What the boundary is, and is not

It is filesystem and process isolation: a separate kernel, a separate process
tree, and no access to host paths that were not shared.

It is not a network boundary. The guest has ordinary outbound connectivity
because the agent has to reach its vendor API, so anything reachable from the
host's network is reachable from a session. Nor is it a credential boundary in the
general case: an agent forwarded into the guest can use whatever the forwarded
sockets can do.

It also does not cover every agent-adjacent tool on a host, by design. It
exists for agentic CLI harnesses run through wrappers (`cc`/`cx`),
where the whole point is reducing blast radius for a process that runs
unattended. Zed's built-in agent (`modules/programs/zed.nix`'s
`trust_all_worktrees`, `modules/aspects/ai-coding-local.nix`'s
`tool_permissions`) runs natively on the host with a GUI and a human present,
which is a different trust model with its own mitigations (interactive
review, no unattended sessions) rather than this one. If a host-level tool
grant like that starts running unattended, it needs this boundary too.

## Extending

**A new harness.** Build its wrappers through the shared factory, use
`flake.lib.agents.mkVmSandbox` to hand `<name>-native` to the session entry
point, add its state directories to the shared table, and have the host
contribute them. If that is not roughly all it takes, the factory boundary is
wrong; report it rather than working around it.

**A new channel.** Add the constant, the guest half, and the host half. Decide
what an untrusted guest may do with the thing behind the socket *before* wiring
it, and prefer a restricted socket over a full one.

**Validation.** The VM layer is a plain guest configuration, not a registry
entry, so it can be built and thrown away:

```sh
timeout 300s nix eval --raw \
  .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath

nix run .#agent-vm-run -- agent-vm-smoke-test   # boots a throwaway guest
```

Booting a guest by its runner alone is not enough: virtiofs shares need their
daemons started first, which is what `agent-vm-run` exists to do.

**Inspecting the guest's own evaluated config from the host flake.**
`microvm.vms.<name>` is a `types.submodule` option, so
`nixosConfigurations.<host>.config.microvm.vms.<name>.config` is the
submodule's own module-instance wrapper (`config`/`options`/`_module`/...),
*not* the guest's evaluated NixOS config; that's one `.config` deeper:

```sh
nix eval .#nixosConfigurations.<host>.config.microvm.vms.<name>.config.config.<path...>
```

e.g. `...config.config.systemd.services.<unit>.serviceConfig` to check a
guest-side systemd unit without a real boot. `.evaluatedConfig` looks like
the obvious accessor and is not it (evaluates to `null` under `nix eval`
without something forcing it). This is a microvm.nix shape, not something
this repo controls; it's vendored, so it's worth restructuring only if the
upstream option shape changes.

Prompt resolution has its own read-only window, so a prompt can be inspected
without spending a session:

```sh
nix run .#agent-prompt-preview -- <harness> <variant>
```

## Invariants

- Exactly one module declares the VM instance.
- The VM layer never names a harness fact; the harness library never names a
  VM concept.
- Shares are mounted at the identical host path.
- The guest runs no Home Manager.
- No channel gives an untrusted guest a capability the host would refuse it.
- A wrapped harness never silently degrades to running on the host; the
  `-native` package is the only bypass, and it is explicit.
