# Agent guide

This is a personal NixOS flake built from dendritic modules.

Evaluate whether changes should be surgical or broad. If a problem is better solved through a larger architectural change, you should propose it to the user.

## Repository model

[flake-parts](https://flake.parts/) composes the outputs. The local `nucleus` module discovers the module tree and generates `flake.nix` from distributed input declarations.

`nucleus` passes every discovered `.nix` file below `modules/` to flake-parts in lexical order, excluding underscore-prefixed paths. Consequently, **every `.nix` file under `modules/` must be a flake-parts module**. Do not place a conventional value-only `default.nix`, package expression, or manually imported helper there; put non-module Nix data outside the module tree, normally under `data/`.

Flake-parts modules are position-independent components. Files under `modules/`
must not use relative paths to reach external repository source. Use
flake-rooted `${self}/...` paths or a richer interface such as `self.data`.
Adjacent assets that are an intrinsic part of a self-contained component may
remain relative. This keeps moving a component from changing its dependencies.

| Path | Responsibility |
|---|---|
| `modules/host-plumbing/` | Host registry, identities, and Home Manager attachment machinery. |
| `modules/host/` | Concrete host declarations and host-only refinements. |
| `hosts/` | Conventional, private host fragments imported only by their owning declaration. |
| `modules/features/` | Reusable capabilities with neutral, typed interfaces. |
| `modules/mechanisms/` | Shared infrastructure other modules build on, each directory or file owning its whole concern. |
| `modules/aspects/` | High-level, composable bundles of features and their interoperability policy. |
| `modules/fleet/` | Typed, public, non-secret facts shared by multiple repository consumers. |
| `modules/serve/services/` | Disabled-by-default hosted-service features exported as `serve-*`. |
| `modules/serve/domains/` | Disabled-by-default public ingress compositions exported as `domain-*`. |
| `modules/de/` | Desktop features; `kde.nix` is the dual NixOS/Home Manager reference. |
| `modules/programs/` | Opinionated, reusable Home Manager program modules. |
| `modules/app-config/` | Experimental package-coupled application configuration exported as wrapper modules. |
| `modules/preferences/` | Settings and identities that follow a person across hosts. |
| `modules/inputs/` | Flake inputs and their integration modules. |
| `modules/utils/` | Shared flake library and maintenance apps. |
| `data/` | Non-module state consumed by Nix: JSON, scripts, text, and value-only Nix files. |
| `docs/` | Durable onboarding material for architecture, contracts, and contributor expectations. |
| `docs/research/` | Exploratory notes that may discuss alternatives or volatile implementation state. |

## Documentation maintenance

Read relevant documents before changing a system it describes, and update that document when an architectural boundary, public contract, or contributor expectation changes.

Files directly under `docs/` are onboarding material. They should explain why a system exists, how its layers compose, who owns each concern, which invariants must hold, and how contributors should extend or validate it. Examples should use illustrative names and values. Do not maintain catalogues of current hosts, consumers, package selections, or other non-durable state that ordinary configuration changes would quickly invalidate; the in-source docstrings are intended to be the authority for those details.

`README.md` files in subdirectories are generated automatically from the `nix run .#mkflakedocs` script, which sources `/** ... */` docstrings from nix files. Keep the docstrings up to date and accurate, but don't regenerate documentation unless requested. Prefer to put durable architecture guidance under `docs/` instead of duplicating it other files.

`docs/research/` is for long-running repo experiments, investigations, and other materials involving unsettled architecture or design decisions.

When making architectural changes, always refresh the relevant documentation. Don't merely append unless your change is strictly additive; the documents should always be kept relevant and concise, without of stale, redundant, or misleading information. This direction also applies to the local `AGENTS.md`.

## Guidance

Flake-related nix commands operate from git; if nix files are added they must be staged to be visible in order to be evaluated.

- Never hand-edit `flake.nix`. Declare inputs through `nucleus.inputs` in an appropriate module, then run:

```sh
nix run .#write-flake
nix flake lock          # only when inputs changed
timeout 120s nix build .#checks.x86_64-linux.nucleus --no-link
```

- Name dendritic-style nix files after their respective modules; don't use `default.nix` for files in the `modules/` directory.

- Always validate your changes. Start with syntax/whitespace and the narrowest affected output. Prefer using timeouts, e.g.

```sh
git diff --check

timeout 60s nix eval --raw \
  .#nixosConfigurations.armatus.config.system.build.toplevel.drvPath

timeout 60s nix eval --json \
  .#nixosConfigurations.armatus.config.hostIdentity

timeout 60s nix eval --raw \
  .#nixosConfigurations.armatus.config.home-manager.users.user.home.stateVersion

timeout 60s nix eval --raw \
  '.#homeConfigurations."user@armatus".activationPackage.drvPath'
```

- Run only the checks relevant to the change. Do not claim a check passed unless it actually ran successfully; if broader validation would pull in an unrelated large host, state the focused validation boundary.

- Where possible, try to build relevant targets to ensure correctness. You can use `nix build` with `--no-link` and `--dry-run` to avoid artifact pollution.

### Keep distinct module classes

- Export NixOS modules as `flake.modules.nixos.<name>`.
- Export Home Manager modules as `flake.modules.homeManager.<name>`.
- Export Nix-on-Droid modules as `flake.modules.nixOnDroid.<name>`.
- Evaluate flake-parts modules only at the outer flake layer.

Do not cross-import NixOS and Home Manager modules. Deferred module types may hide this mistake until evaluation.

Likewise, distinguish
`home-manager.flakeModules.home-manager` (flake-parts),
`home-manager.nixosModules.home-manager` (NixOS integration), and
`home-manager.lib.homeManagerConfiguration` (standalone builder).

## Configuration ownership

- **Programs** configure one Home Manager program with reusable, refinable defaults. Importing a program module should enable it.
- **Features** implement a coherent capability with neutral, typed options. A feature may export both NixOS and Home Manager modules.
- **Aspects** compose features into a high-level, reusable use case and may wire fleet policy into those features.
- **Preferences** hold personal identity and choices, not reusable policy.
- **Host-user attachment modules** contain the final refinements unique to one user on one host.

Read [`docs/modules.md`](docs/modules.md) before introducing or moving module
ownership boundaries. Fleet state is typed, public, and non-secret; hosts must
consume it directly rather than evaluating another host. Repeated policy should
move from host fragments to the narrowest reusable typed module only when its
semantics and lifecycle are shared. Repeated concrete values belong in fleet
only when every consumer intentionally shares one source of truth.

Use `lib.mkDefault` for policy intended to be refined. Preferences and host-specific refinements usually use ordinary definitions. Module order is not “last definition wins”; use priorities, `lib.mkBefore`, and `lib.mkAfter`. Reserve `lib.mkForce` for deliberate conflict resolution.

### Hosted services and domains

Read `docs/serve.md` before changing `modules/serve/` or a host's serve/domain composition. Service modules behave like opinionated NixOS features, but export as `flake.modules.nixos.serve-<name>` and must expose `serve.<name>.enable = lib.mkEnableOption ...`; importing one must not activate it. Domain modules export as `flake.modules.nixos.domain-<name>`, import their curated service set, and add reverse-proxy routes and public firewall openings only for explicitly enabled services. Shared proxy infrastructure such as `serve-caddy` is imported once by the host. A host may instead import a service directly, in which case the host owns any ingress policy.

Keep concrete addresses, storage paths, and host-specific refinements in host
modules rather than embedding them in reusable service modules.

### Non-configuration data

Use `${self}/...` for ordinary flake-root-relative source paths outside
`data/`, including host entrypoints and test fixtures. A relative path is
acceptable only for an adjacent asset that belongs to the component itself,
such as a utility's script or its colocated test. Prefer a richer repository
interface when one exists.

`modules/data.nix` exposes `self.data` as the common boundary for files under `data/`:

- `self.data.path "..."` returns a store-backed path/string for imports or file consumers.
- `self.data.read "..."` reads text.
- `self.data.readJSON "..."` parses JSON.
- `self.data.readLines "..."` and `readNonEmptyLines` normalize line-oriented files.
- `self.data.vars` provides named, normalized representations used in several places.

This boundary also avoids a dendritic import trap. A helper `.nix` file placed beside its consumer under `modules/` would itself be discovered by `nucleus` and evaluated as a flake-parts module. Moving the helper outside `modules/` makes direct relative imports awkward and sensitive to relocating the consumer. `self.data` provides a stable flake-root-relative route to those files instead.

Keep large configuration blobs, scripts in their native language, and value-only Nix expressions in `data/`, mirroring the consuming feature or program when useful. Extend `self.data.vars` for genuinely shared normalized values rather than repeating parsing logic. Do not move credentials into `data/`; it is ordinary flake source, not secret storage.

Prefer this interface over scattered `${self}/data/...` paths or repeated `builtins.readFile`/JSON parsing. It also keeps value-only `.nix` files out of the auto-imported module tree.

Nix evaluates the Git-backed flake source, so new untracked files can be invisible during flake evaluation. Do not stage unrelated files as a workaround; use validation that respects the current index, or explain when a new file must be tracked.

## Hosts and user environments

`modules/host-plumbing/registry.nix` turns `host.<name>` declarations into the configuration output of the host's declared `class`—`nixosConfigurations.<name>` or `nixOnDroidConfigurations.<name>`—and, when enabled, deployment or ISO apps. Every host receives a read-only `hostIdentity` containing `name`, `description`, `primaryUser`, and `stateVersion`. Use it instead of repeating host metadata. The registry also derives the host name, platform, and system/Home Manager state version defaults.

`stateVersion` is compatibility metadata and should NOT be advanced with nixpkgs or home-manager versions.

Home Manager environments are attached at `host.<name>.userEnvironment.<username>` and combine:

1. Home Manager modules contributed by imported host features.
2. Explicitly attached reusable and host-user Home Manager modules.

`integrated` mode activates through the host system; `standalone` mode, available to NixOS hosts only, exposes `homeConfigurations."<user>@<host>"`. Both modes must consume the same module graph. Shared modules must therefore avoid integrated-only arguments such as `osConfig`; use the Home Manager `userEnvironment` identity when host context is needed.

A reusable NixOS feature contributes user configuration through:

```nix
userEnvironment.sharedModules = [ homeModule ];
```

It must not configure `home-manager.users` directly—the registry owns activation and attachment. Contributions are evaluated only when the host imports the feature and has a user environment.

Keep each host declaration as the assembly point for identity, reusable module
selection, capabilities, and its private fragments. Conventional NixOS and Home
Manager fragments belong under `hosts/<hostname>/`, grouped by ownership and
exposed through that host's `hosts/<hostname>/default.nix` entrypoint, and
imported only by that host through
`config.flake.lib.importHostFragments "<hostname>"`. That entrypoint is a
function of one attribute set which ignores unused arguments with `{ ... }`;
give a fragment tree what it needs through those arguments instead of letting it
read `config.flake`. Do not export private fragments or place them under
the nucleus-discovered `modules/` tree. When repeated host policy has genuinely
shared semantics and lifecycle, promote it to the narrowest reusable typed
module instead of cross-importing a private fragment.
