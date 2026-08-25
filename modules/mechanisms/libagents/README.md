## libagents

# flake.lib.agents

Shared definitions consumed by every harness feature module
(`modules/features/claude-code.nix`, `modules/features/codex.nix`, and any
future addition). This is the harness *layer*: it knows about tool lists,
prompt fragments, skills and `AGENTS.md`. It must never mention vsock,
virtiofs, systemd units, or anything belonging to the VM layer
(`modules/mechanisms/libagents/vm.nix`) — see the layering rule in
`docs/agents.md`.

- `tools` / `toolsMarkdown` — the CLI tool set every harness's shell
fragment advertises, and its rendering as a markdown bullet list.
- `fragments` — reusable preamble text blocks (`shell`, `rtk`, `headroom`,
`memory`, `serena`). Each is plain text; harnesses are responsible for
concatenating the fragments they want and injecting the result at
whatever depth their own module (`--append-system-prompt`,
`developer_instructions=`, ...) requires.
- `collectSkills` — recursively scans a skills root for `SKILL.md`
directories, keyed by their path with `/` flattened to `-`.
- `context` — the shared `AGENTS.md` context text.
- `stateDirs` / `stateDirsFor` — the `$HOME`-relative directories each
harness and component keeps live state in, and a helper that makes them
absolute for one home. Declared here because the VM layer is forbidden
from naming any of them (`implementation-guide.md` Phase 6) and the
harness modules themselves are Home Manager modules, which a NixOS
configuration cannot read back — a standalone `userEnvironment`
attachment is not evaluated during `nixos-rebuild` at all. A plain table
in the harness layer is therefore the only place both sides can agree on.
- `environmentFor` — environment variables that must hold the *same* value
on the host and inside the guest, for one home directory.

- `mkPrompt` — resolves a `(harness, model, variant)` prompt into the three
depths a harness can inject at (`system`, `preamble`, `context`), from a
layered `common -> byHarness -> byVariant -> byModel` declaration. See
its doc comment below for the layer shape. `system` is a `path` (or
`null`); `preamble` and `context` are single strings — never a list of
flags — because `--append-system-prompt`-style options do not
accumulate across repeated invocations.

## prompt-preview

# agents.promptPreview / `agent-prompt-preview`

A read-only window onto `flake.lib.agents.mkPrompt`'s output, so a prompt
can be inspected without starting a session.

Harness feature modules (`claude-code.nix`, `codex.nix`, ...) publish each
`(harness, variant)` prompt they resolve under
`config.agents.promptPreview.<harness>.<variant>`, a plain `{ system;
preamble; context; }` attrset — no isolation/VM concepts involved, this is
purely the harness layer. The `agent-prompt-preview` package/app reads that
attribute back out of an evaluated `homeConfigurations.<name>` via `nix
eval`, printing each of the three depths separately.

This module's `homeManager.agents-prompt-preview` output only declares the
option; each harness feature module that writes to it
(`claude-code.nix`, `codex.nix`) imports it directly, so either one is
usable standalone without also pulling in a combining module. The module
carries an explicit `key` (its own output attribute path, as in
`ssh-known-hosts`) so importing it from more than one harness at once
dedupes instead of failing at eval time with "option ... is already
declared" — deferred/value-imported modules have no path to dedupe by
otherwise.

Usage: `nix run .#agent-prompt-preview -- claude plain` (add a third
argument to pick a `homeConfigurations` name other than `user@apc`).

## selector-loop

# flake.lib.agents.{mkSelectorLoop, mkHarnessWrappers}

Implemented per the deviation recorded in `.claude/handoff-472dce40.md`:
an earlier design's literal "harness factory" (model/effort as reserved
cross-harness words,
`native` as a selector) was replaced with this narrower design after
discussion. What genuinely generalizes across `cc`/`ccs`/`cx`/`cxs` turned
out to be smaller than the guide scoped it: harnesses keep their own
selector vocabulary (`haiku|sonnet|opus` vs `luna|terra|sol`, `--effort` vs
`-c model_reasoning_effort=`, ...) as their own case arms, handed to this
factory as literal bash text — not a declarative selector DSL, which would
be over-engineering for text that already differs per harness in both
membership and downstream flag shape.

Two pieces:

- `mkSelectorLoop` — the shared `while/case` skeleton: `--` handling,
"later selector wins" (implicit case-statement ordering — nothing here
enforces it, it falls out of `case` re-matching each arg once), and the
one line of `--help` footer text that was identically duplicated between
`claude-code.nix` and `codex.nix`. Everything else in a harness's
`--*-help` output (usage line, per-selector explanations) stays with the
harness, since that text is harness-specific.

- `mkHarnessWrappers` — builds a `<name>-native` package (the bare,
unsandboxed session invocation: selector parsing through the final
exec) and a `<name>` package (a thin dispatcher that either execs
`<name>-native` directly, when `sandbox` is null, or hands off to
whatever `sandbox` returns — bubblewrap today, a microVM in a later
phase). `native` is no longer a selector word: running `<name>-native`
directly *is* the bypass, so there is no runtime `sandbox` flag to
thread through one script and no collision surface to guard with an
eval-time assertion (the guide's Phase 3 called for one; it has nothing
left to protect under this design — see the handoff for why that
requirement was dropped rather than carried forward speculatively).

Forward-looking Phase 3 pieces from the guide (`stateDirs`, `components`,
`needs` fields for the VM layer) are intentionally absent here — Phase 4
hasn't clarified what the VM layer needs from a harness declaration yet,
and guessing ahead of it risks the wrong shape. Don't add them speculatively.

## vm-channels

# flake.lib.agents.vmChannels

The constants both halves of a Phase 5 channel have to agree on, in one
place so the guest (`vm.nix`) and the host (`vm-host.nix`) can never drift
apart. Nothing here evaluates to a module; it is a plain lookup table plus
the CID derivation.

A channel is a unix socket in the guest proxied over `AF_VSOCK` to a
listener on the host, which hands the connection to the real socket. The
guest always dials the well-known host CID (2) on the channel's port; the
host listener binds `VMADDR_CID_ANY`, so it serves every guest and nothing
has to be re-derived when a second VM appears.

**Ports are host-wide, CIDs are per-VM.** Two guests asking for the same
channel dial the same port and reach the same listener — which is correct,
since the thing behind it (this machine's nix daemon, this user's
gpg-agent) is singular anyway. What must stay unique is `microvm.vsock.cid`,
hence `cidFor`: derived from the VM's name the way `macFor` derives a MAC in
`vm.nix`, so it is stable across evaluations and does not need a registry
to hand out numbers. Collisions are a birthday problem over 65533 values,
not a correctness guarantee; if two VMs ever collide, the second one fails
to start with QEMU complaining about the CID, which is loud enough to fix
by renaming.

The port numbers themselves are arbitrary but must not move once a guest
image is in the wild: a guest built before a renumbering would dial a port
nothing listens on and hang rather than fail.

**This is not an authenticated channel.** Any VM on this host with vsock
access can dial these ports; the host side does not know which guest it is
talking to. That is why the nix daemon listener runs as an *untrusted* nix
user (see `vm-host.nix`) and why the gpg channel forwards the restricted
`S.gpg-agent.extra` socket, which signs but refuses to export a key.

## vm-host

# `flake.modules.nixos.agent-vm`

The host half of the agent VM: it owns the VM declaration and it owns the
host-side end of every channel. A mechanism rather than a feature — no host
would name "runs a VM
manager for coding agents" as a capability it wants; the harnesses want it,
and this serves them (`docs/modules.md` §"Reusable modules").

**One owner for the VM** (`docs/modules.md` §"Shared instances"). This
module declares `microvm.vms.<name>` exactly once. Harness modules must
never declare a VM of their own: several harnesses are meant to share one
guest, so a second declaration is either an outright conflict or an
accidental merge, and anything that refcounts sessions over the instance
(Phase 7) becomes meaningless. Harnesses contribute the facts that are
theirs — `projectRoots` and `stateDirs` — and may raise `enable` as an
`mkDefault`. `hostUser`, `uid`, `vcpu`, `mem` and the vsock
CID are platform policy: this module's defaults, the host's to override, and
never a harness's business.

## The channels

Both are the same shape: a systemd socket listening on `AF_VSOCK` with
`Accept = true`, handing each connection to socat, which connects to the
real unix socket. The guest dials CID 2 on the port; see `vm-channels.nix`
for why the listener binds any CID rather than the guest's.

- **nix daemon.** The listener runs as `nixProxyUser`, a system account
that is deliberately *not* in `nix.settings.trusted-users`. The host
daemon authenticates by peer credentials, so whatever uid this proxy runs
as is the identity the whole guest gets: run it as root and the guest can
ask the host to substitute from any binary cache it likes, which the guide
is emphatic must be refused. Untrusted is not read-only: an untrusted
client may still build derivations and add paths, which is the whole
point — it just cannot tell the daemon *where to trust content from*.
The account must appear in `allowed-users`, which an assertion checks
rather than defines (see below).
- **gpg-agent.** The listener runs as `hostUser` and connects to the
**restricted** socket — `agent-extra-socket`, which signs and decrypts but
refuses to export a key — resolved by asking `gpgconf` at connection time
rather than hardcoding `/run/user/<uid>/gnupg/...`, since that path is
both uid-dependent and version-dependent. Because it lives under
`/run/user/<uid>`, the channel only works while that user has a session on
the host; with no session there is no agent to forward to, and the guest
sees a connection refused. That is the honest failure — a signature needs
the human at the machine anyway.

## Lifecycle (Phase 7)

The VM starts on demand and stops once nothing needs it. `agent-vm-session`
(`environment.systemPackages`) is the one entry point: `agent-vm-session --
<command>` starts the guest if it is not already up, waits for its sshd,
and runs `<command>` over ssh in a `systemd-run --scope` of its own — see
that script's doc comment (next to `mkSessionScript` above) for why a scope
needs no explicit release step, what `agent-vm-linger-hold.service` is for,
and the two traps in microvm.nix's generated unit (`Restart = "always"`,
`StopWhenUnneeded`'s lack of a grace period) that shaped it. Not yet called
by any harness wrapper — that wiring is Phase 8's cutover, not this
module's.

`agent-vm-stop` (`mkStopScript`, next to `mkSessionScript`) is the manual
counterpart: drops the linger-hold reference immediately rather than
waiting out `lifecycle.lingerSeconds`, for a human who knows they are done
for a while and would rather not leave the guest idling. It is a pure
early-release, not a kill — an active session's own referrer keeps the
guest up regardless, exactly as if the automatic linger had simply expired
sooner.

The `security.polkit.extraConfig` rule is what lets `hostUser` — an
unprivileged account — start and stop these specific units at all;
`systemctl start/stop` on a system unit is refused by default otherwise.

## Why the microvm.nix host module, this early

It generates `microvm@<name>.service` with `microvm-virtiofsd@<name>.service`
as a dependency, so the "start the daemons yourself" problem that
`packages.agent-vm-run` exists to solve stops being the deployment path
(`agent-vm-run` stays a dev tool for throwaway guests like the smoke test).
Those daemons run as root, which is what makes store paths appear correctly
owned inside the guest. And it gives Phase 7 exactly one unit to hang
session refcounting off.

`autostart` defaults to **false**: enabling this module should cost a build,
not a permanently running VM. Phase 7 decides when the guest actually runs.

`boot.kernelModules` and the udev rule exist because a guest with a channel
has `microvm.vsock.cid` set, so QEMU opens `/dev/vhost-vsock`; without the
module loaded the node does not exist, and without the rule only root may
open it, which breaks the unprivileged `agent-vm-run` path for no benefit
(the `kvm` group already gates who may run VMs at all).

## vm-run

# `agent-vm-run`

One command for "boot an agent VM on this machine and get a shell", so
manual verification doesn't start with a five-line shell incantation.

`nix run .#nixosConfigurations.<vm>.config.microvm.declaredRunner` is not
enough on its own: it executes only the runner's `bin/microvm-run` (QEMU),
while each `proto = "virtiofs"` share needs a `virtiofsd` already listening
on a socket path that is **relative to the current directory**. Miss that
and QEMU exits immediately with `Failed to connect to
'<vm>-virtiofs-<tag>.sock'`. This wrapper builds the runner, starts the
daemons in a scratch state directory, waits for their sockets, then runs
QEMU in the foreground and tears the daemons down on exit.

```
nix run .#agent-vm-run -- agent-vm-smoke-test
ssh -p 2222 user@localhost
```

**Privileged by default, and that matters.** The runner's
`bin/virtiofsd-run` is a supervisord config with `user=root`, so this runs
it under `sudo` unless it is already root. `--unprivileged` skips sudo and
invokes each `virtiofsd` from that config directly, which boots fine and
preserves path identity, but **squashes ownership**: an unprivileged
virtiofsd cannot present files owned by other users, so everything on the
`/nix/store` share appears as `nobody:nogroup` (65534) inside the guest.
That is not cosmetic — `logrotate` refuses a config file it does not see as
root-owned, so `logrotate-checkconf.service` fails on boot and anything
else that checks ownership of store paths may follow. Files owned by the
invoking user (project roots) still map correctly, which is why path
identity checks pass either way. Use `--unprivileged` for a quick boot
test, not to judge whether the guest is healthy.

This deliberately does not install a systemd unit or a persistent state
directory. VM lifecycle management belongs to microvm.nix's own host
module (`microvm.vms.<name>`, which generates a `microvm@<name>.service`
that already depends on its virtiofsd units and carries the
reference-counted linger policy — see `vm-host.nix`) rather than to this
wrapper, which stays a dev tool for throwaway guests. Everything below is
scoped to running one VM interactively, from a directory outside the flake
(a QMP socket dropped into the source tree makes the flake itself
unevaluable).

## vm-smoke-test

# `nixosConfigurations.agent-vm-smoke-test`

Phase 4's acceptance test target — "get *any* VM booting, with correct
path identity. No harnesses yet." Not part of the host registry
(`modules/host-plumbing/registry.nix`): it isn't a real fleet host, has no
`hostIdentity`, and is meant to be built and thrown away, not deployed.

**Running it:** `nix run .#agent-vm-run -- agent-vm-smoke-test`, then
`ssh -p 2222 user@localhost`. Plain
`nix run .#...config.microvm.declaredRunner` is *not* enough — it starts
QEMU without the `virtiofsd` daemons every `proto = "virtiofs"` share
needs, and dies with `Failed to connect to
'agent-vm-smoke-test-virtiofs-ro-store.sock'`. See
`modules/mechanisms/libagents/vm-run.nix` for what the wrapper does, why it wants
`sudo`, and what `--unprivileged` costs you.

Phase 5 added the nix-daemon and gpg-agent channels here rather than in a
second guest. They need `agent-vm.enable = true` on the host (see
`modules/mechanisms/libagents/vm-host.nix`); without it the guest boots
normally and both proxies just fail to connect.

Phase 6 added the harness state directories as read-write shares. Those
come from the host and are not created by this configuration, so building
it on a machine that lacks them is fine but *running* it there is not:
virtiofsd refuses a source directory that does not exist. On a host with
`agent-vm.enable`, systemd-tmpfiles has already made them.

The in-guest acceptance checks themselves live in untracked working notes
(not part of this repository).

## vm

# flake.lib.agents.mkAgentVm

The VM layer. Must never mention `~/.claude`, headroom, or a model name — that's
the harness layer's job (`libagents.nix`, `selector-loop.nix`). This layer
only knows about shares, networking, channels, and the guest's own NixOS
configuration; it must never be handed a harness's prompt text or tool
list.

`mkAgentVm { name, hostUser, projectRoots, uid ? null, authorizedKeys ? [],
vcpu ? 2, mem ? 4096, stateDirs ? [], guestEnvironment ? {}, channels ? {},
lifecycle ? {} }`
returns a NixOS module (a plain guest config, not a `nixosConfigurations.*`
entry — the caller decides how to instantiate it, matching how every other
module in this flake stays a value rather than wiring itself in).

**Shares and identity (Phase 4).** Store share (read-only virtiofs + a
tmpfs-backed writable overlay, so the guide's "known failure mode" —
overlayfs upper dir on virtiofs/9p — never applies here, since the
overlay's upper directory lives on the guest's own root instead of a
share), one virtiofs share per `projectRoots` entry mounted at the
**identical host path**, SSH reachable via a forwarded port over QEMU user
networking, and a guest user whose **name and home path** match `hostUser`.

**Channels (Phase 5).** `channels` is the seam the harness layer eventually
declares through: it says *what capability the guest needs*, and this
function decides that the capability is a vsock proxy. Each channel is a
unix socket in the guest, socket-activated per connection, forwarded to a
listener on the host (`vm-host.nix`); the constants both ends share live in
`vm-channels.nix`.

```nix
channels = {
nixDaemon.enable = true;
gpgAgent = {
enable = true;
certificates = [ "<armored public key>" ];
ultimatelyTrusted = [ "<fingerprint>" ];
};
};
```

- `nixDaemon` replaces the guest's own `nix-daemon` with a proxy onto the
**host's** daemon, so a build in the guest lands in the host store and is
already there when the guest is gone. The guest's local daemon is
disabled outright rather than left running on another path: two daemons
over one store is how you corrupt a database, and a fallback that
silently builds locally would hide a broken channel behind a slow build.
`NIX_REMOTE=daemon` is set explicitly because nix's own heuristic
("is the store writable?") sees a read-only `/nix/store` share and a
writable overlay and is not worth trusting to guess right.
- `gpgAgent` forwards the **restricted** agent socket. The guest gets the
public keyring built from the certificates passed in — never copied out
of anyone's `$HOME` — so `git commit -S` finds the key, while the private
key stays on the host's smartcard and every signature needs whatever the
host's agent asks for (a touch, a PIN). `certificates` and
`ultimatelyTrusted` are parameters rather than a reach into
`self.data.identities` so this layer keeps knowing nothing about who its
caller is; the host module supplies the defaults.

Enabling any channel sets `microvm.vsock.cid` (derived from `name`, so it
is stable and unique without a registry), which makes QEMU want
`/dev/vhost-vsock` — see `vm-host.nix` for the host-side permissions that
need.

**State directories (Phase 6).** `stateDirs` is a list of host directories
shared read-write at the identical path, exactly like `projectRoots` — the
distinction is entirely in who contributes them and why, not in what this
function does with them, so they are kept as two lists rather than merged
into one. They carry the agent's memory, sessions and credentials across
guest restarts.

This function must never *name* one of those directories: which state a
harness keeps, and where, is the harness layer's fact
(`flake.lib.agents.stateDirs`). Same for `guestEnvironment`, an opaque
attrset of `name = value` pairs written into the guest's
`environment.variables`; the host passes `CLAUDE_CONFIG_DIR` through it
without this layer learning what claude is.

The guest runs **no Home Manager**, and that is load-bearing rather than
incidental: Home Manager symlinks at file granularity, so a guest
generation over the same shared `~/.claude` would rename the host
generation's `settings.json` out of the way on every boot. The host's
generation is the sole manager; the guest gets packages and wrappers only.

**`lifecycle` stays unwired.** Phase 7 turned out to need nothing from the
guest side at all: the VM starts and stops as a host-managed systemd unit
(`microvm@<name>.service`), refcounted by host-side transient units the
guest never hears about — see `vm-host.nix`'s "Lifecycle (Phase 7)"
section. The parameter is kept, still accepting and ignoring whatever is
passed, so a caller built against the documented signature doesn't break;
nothing currently passes it.

`uid`, if given, is the host user's numeric uid. The default virtiofs
`securityModel = "none"` preserves numeric ownership as-is rather than
translating it, so a mismatched guest uid makes shared files look
wrong-owned from inside the guest even though the bytes are identical;
passing it keeps a `touch`'d file's ownership sane on both sides. Leaving
it `null` still boots and shares files, just without that cosmetic
guarantee — acceptable for this phase's "any VM boots, path identity
holds" bar.
