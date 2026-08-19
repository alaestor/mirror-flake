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
| App config | A package-coupled configuration exported as a wrapper module, consumed by a thin program adapter. It owns configuration that must travel with the package rather than with a user's Home Manager state. |
| Feature | A coherent capability with neutral typed options. It may export NixOS and Home Manager implementations separately. |
| Aspect | A high-level, composable bundle of features that wires their interoperability or shared policy for a use case. |
| Serve | A network-hosted feature with an explicit disabled-by-default enable option. |
| Domain | A high-level ingress aspect for a public domain. It imports a curated serve set, but opens routes and ports only for explicitly enabled services. |

An aspect is the repository term for high-level reusable composition. Do not use
“profile” or “featureset” for that meaning; retain “profile” only when it is an
upstream application's own term.

### Dependencies between features

A feature may import another feature. That import expresses a prerequisite, and
it is not a reason to introduce an aspect. Aspects express a domain interest —
“gaming”, “coding” — and must not be used to describe a dependency
relationship between modules.

Import a feature from a feature when the importing module is an extension of
that base, and the base is meaningfully usable on its own or shared by more
than one consumer. Otherwise write the dependency into the module that needs
it, and rip it out into shared infrastructure only once a second consumer
exists. Anticipating that consumer produces a shared module with one caller
and no evidence about the shape of the seam.

App config is an experimental kind. It lives in `modules/app-config/` and is
exported through `flake.wrappers` rather than a module class registry, so the
Home Manager program module for the same application stays a thin adapter over
it. Prefer a plain program module unless configuration genuinely belongs to the
package; see [package-coupled application configuration](research/appconfig.md)
for the rationale and its open questions.

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
module classes.

Every flake-parts module under `modules/` is a position-independent component.
Its dependencies must not change when the file moves within the module tree, so
it must not use relative paths to reach external repository source. Resolve
ordinary source from the flake root with `${self}/...`; resolve `data/` through
the richer `self.data` interface. Adjacent scripts, templates, or tests that are
intrinsic parts of a self-contained component may remain relative.

Host-only fragments live outside the nucleus-discovered module tree under
`hosts/<hostname>/`. Each host tree exposes one conventional `default.nix`
entrypoint that may use relative paths internally to assemble its fragments.
The position-independent host declaration reaches only that entrypoint, through
`flake.lib.importHostFragments "<hostname>"`; private fragments are not exported
as reusable modules.

Every entrypoint is a function of one attribute set and receives the same
arguments, ignoring what it does not use with `{ ... }`. Repository-wide facts
a fragment tree needs are passed in through those arguments rather than reached
for, so no private fragment evaluates `config.flake`, and gaining a dependency
is not a signature change at the call site.

For host and Home Manager attachment mechanics, see
[Hosts and user environments](hosts-and-homes.md). For hosted ingress, see
[Hosted services and domains](serve.md).
