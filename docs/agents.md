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
| Harness library | `flake.lib.agents` | Prompt fragments and resolution, tool lists, skills, selector-loop and wrapper factories, and the table of per-harness state directories. |
| Harness feature | `flake.modules.homeManager.<harness>` | One CLI: its packages, prompt depths, settings, and the `sandbox` seam that hands a session to the isolation boundary. |
| VM layer | `flake.lib.agents.mkAgentVm` | A guest NixOS configuration: shares, guest identity, sshd, and the guest half of each channel. |
| Host mechanism | `flake.modules.nixos.agent-vm` | The single VM instance, the host half of each channel, session lifecycle, and the `agent-vm-session` entry point. |
| Host | `host.<name>` and its fragments | Which harnesses are attached, which trees the agent may work on, and platform sizing. |

Everything except the harness features lives in `modules/mechanisms/libagents/`.
It is a mechanism, not a feature: no host asks for "a VM manager for coding
agents", it gains one as a consequence of attaching a harness
([Module ownership](modules.md), §Reusable modules).

### The layering rule

The VM layer must never name a harness fact: not a config directory, not a
model, not a prompt. It receives opaque lists (`projectRoots`, `stateDirs`) and
opaque `name = value` pairs (`guestEnvironment`), and it is the harness layer's
job to know what they mean. Conversely the harness library must never mention
vsock, virtiofs, or systemd units.

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

State directories are a harness fact, contributed by the host that attaches the
harness. A standalone Home Manager environment is not evaluated during a NixOS
rebuild, so a harness module cannot contribute them directly; the shared table
in `flake.lib.agents.stateDirs` is what lets both sides agree.

## Shares and state

Every share is mounted at the **identical host path**. Path identity is what
makes a store path, a `result` symlink, a `gcroot`, or an error message mean the
same thing on both sides, and it is why a session can be handed a host-built
wrapper by store path and simply execute it.

Two contribution points, kept separate because they answer different questions:

- `projectRoots`: what the agent may work on. Fixed at guest boot; a session
  outside them is refused rather than the boundary widening to fit.
- `stateDirs`: what must outlive the guest: sessions, memories, caches,
  credentials.

Anything not shared is ephemeral. The guest's root filesystem is tmpfs, so a
home directory, shell history, or configuration file that no share covers is
gone at shutdown.

The ownership rule: the guest runs no Home Manager. Home Manager symlinks at
file granularity, so a second generation over a shared directory renames the
first one's files out of the way. The host's generation is the sole manager of
managed files; the guest gets packages, wrappers, and live state only.

## Channels

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

## Extending

**A new harness.** Build its wrappers through the shared factory, give it a
`sandbox` function that hands `<name>-native` to the session entry point, add
its state directories to the shared table, and have the host contribute them. If
that is not roughly all it takes, the factory boundary is wrong; report it
rather than working around it.

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
