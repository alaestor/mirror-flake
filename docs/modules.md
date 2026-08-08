# Module ownership

This flake separates reusable configuration policy from repository composition
and state. Choose the narrowest owner that can express a behavior through a
typed, refinable interface; importing a module must not be a substitute for an
explicit ownership boundary.

## Reusable modules

Reusable modules are exported in the namespace for their target module system.
They may be composed by hosts, aspects, or attachments, but do not know which
concrete host consumes them.

| Kind | Owns |
|---|---|
| Program | One Home Manager program and its reusable, refinable defaults. Importing it enables that program. |
| Feature | A coherent capability with neutral typed options. It may export NixOS and Home Manager implementations separately. |
| Aspect | A high-level, composable bundle of features that wires their interoperability or shared policy for a use case. |
| Serve | A network-hosted feature with an explicit disabled-by-default enable option. |
| Domain | A high-level ingress aspect for a public domain. It imports a curated serve set, but opens routes and ports only for explicitly enabled services. |

An aspect is the repository term for high-level reusable composition. Do not use
“profile” or “featureset” for that meaning; retain “profile” only when it is an
upstream application's own term.

Exported modules remain in the flat target-specific registries such as
`flake.modules.homeManager`. Aspect ownership is conveyed by the
`modules/aspects/` path and module docstrings, not an `aspect-` name suffix or
an additional registry namespace.

## Repository composition and state

These concepts are not generic reusable configuration modules.

| Kind | Owns |
|---|---|
| Fleet | Typed, public, non-secret facts intentionally shared by more than one repository consumer. It never exposes an evaluated host configuration. |
| Host | One concrete machine's identity, compatibility baseline, selected reusable modules, and private implementation fragments. |
| Preference | A person's identity and choices that follow them across hosts, rather than reusable policy. |
| Attachment | The final Home Manager refinements for one user on one host, plus that attachment's activation mode. |

Fleet facts have one declared source of truth. Service credentials, storage
paths, and machine topology remain owned by the relevant host or secret system.
Hosts consume fleet values directly; they must not evaluate another host to
discover shared state.

## Promotion rule

Repeated policy is an architectural signal. When substantially identical policy
appears in private host fragments, promote it to the narrowest reusable typed
module—normally a program, feature, or aspect—when it has shared semantics and
lifecycle. Do not eliminate duplication with unstructured imports.

Move repeated concrete values to fleet only when every consumer intentionally
shares one fact and one owner. Similar-looking machine facts with independent
ownership remain host-local.

## Composition boundaries

Outer flake-parts modules define fleet and host registries and export reusable
modules. NixOS, Home Manager, and Nix-on-Droid implementations remain separate
module classes. Host-only fragments live outside the nucleus-discovered module
tree under `hosts/<hostname>/`; their host assembly module imports them directly
and they are not exported as reusable modules.

For host and Home Manager attachment mechanics, see
[Hosts and user environments](hosts-and-homes.md). For hosted ingress, see
[Hosted services and domains](serve.md).
