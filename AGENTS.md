# Agent guide

This is a personal NixOS flake built from dendritic modules. Keep changes small,
preserve unrelated worktree state, and validate only the outputs a change can
affect.

## Repository model

[flake-parts](https://flake.parts/) composes the outputs,
[import-tree](https://github.com/vic/import-tree) loads the module tree, and
[flake-file](https://github.com/vic/flake-file) generates `flake.nix`.

`flake.nix` passes `modules/` to `import-tree`. Consequently, **every `.nix` file
under `modules/` must be a flake-parts module**. Do not place a conventional
value-only `default.nix`, package expression, or manually imported helper there;
put non-module Nix data outside the module tree, normally under `data/`.

| Path | Responsibility |
|---|---|
| `modules/host-plumbing/` | Host registry, identities, and Home Manager attachment machinery. |
| `modules/host/` | Concrete host declarations and host-only refinements. |
| `modules/features/` | Reusable capabilities and compositions. |
| `modules/serve/services/` | Disabled-by-default hosted-service features exported as `serve-*`. |
| `modules/serve/domains/` | Disabled-by-default public ingress compositions exported as `domain-*`. |
| `modules/de/` | Desktop features; `kde.nix` is the dual NixOS/Home Manager reference. |
| `modules/programs/` | Opinionated, reusable Home Manager program modules. |
| `modules/profiles/` | Reusable user-environment roles, such as `workstation`. |
| `modules/preferences/` | Settings and identities that follow a person across hosts. |
| `modules/inputs/` | Flake inputs and their integration modules. |
| `modules/utils/` | Shared flake library and maintenance apps. |
| `data/` | Non-module state consumed by Nix: JSON, scripts, text, and value-only Nix files. |
| `docs/hosts-and-homes.md` | Detailed host and Home Manager architecture. |
| `docs/serve.md` | Hosted-service and public-domain composition architecture. |

Read `docs/hosts-and-homes.md` before changing host registration, identities,
Home Manager modes, profiles/preferences, or feature contribution plumbing, and
keep it synchronized with such changes.

### Keep module classes separate

- Export NixOS modules as `flake.modules.nixos.<name>`.
- Export Home Manager modules as `flake.modules.homeManager.<name>`.
- Evaluate flake-parts modules only at the outer flake layer.

Do not cross-import NixOS and Home Manager modules. Deferred module types may
hide this mistake until evaluation. Likewise, distinguish
`home-manager.flakeModules.home-manager` (flake-parts),
`home-manager.nixosModules.home-manager` (NixOS integration), and
`home-manager.lib.homeManagerConfiguration` (standalone builder).

## Configuration ownership

The legacy migration established these boundaries:

- **Programs** configure one Home Manager program with reusable, refinable
  defaults. Importing a program module normally enables it.
- **Features** assemble programs or implement a coherent capability. A feature
  may export both NixOS and Home Manager modules.
- **Profiles** bundle features into a reusable user-environment role.
- **Preferences** hold personal identity and choices, not reusable policy.
- **Host-user attachment modules** contain the final refinements unique to one
  user on one host.

Use `lib.mkDefault` for policy intended to be refined. Preferences and
host-specific refinements usually use ordinary definitions. Module order is not
“last definition wins”; use priorities, `lib.mkBefore`, and `lib.mkAfter`.
Reserve `lib.mkForce` for deliberate conflict resolution.

### Hosted services and domains

Read `docs/serve.md` before changing `modules/serve/` or a host's serve/domain
composition. Service modules behave like opinionated NixOS features, but export
as `flake.modules.nixos.serve-<name>` and must expose
`serve.<name>.enable = lib.mkEnableOption ...`; importing one must not activate
it. Domain modules export as `flake.modules.nixos.domain-<name>`, import their
curated service set, and add reverse-proxy routes and public firewall openings
only for explicitly enabled services. Shared proxy infrastructure such as
`serve-caddy` is imported once by the host. A host may instead import a service
directly, in which case the host owns any ingress policy.

Lanser is currently the only server host and the only consumer of serve/domain
modules. Keep concrete addresses, storage paths, and host-specific refinements
there rather than embedding them in reusable service modules.

### External data

`modules/data.nix` exposes `self.data` as the common boundary for files under
`data/`:

- `self.data.path "..."` returns a store-backed path/string for imports or file
  consumers.
- `self.data.read "..."` reads text.
- `self.data.readJSON "..."` parses JSON.
- `self.data.readLines "..."` and `readNonEmptyLines` normalize line-oriented
  files.
- `self.data.vars` provides named, normalized representations used in several
  places.

This boundary also avoids a dendritic import trap. A helper `.nix` file placed
beside its consumer under `modules/` would itself be discovered by `import-tree`
and evaluated as a flake-parts module. Moving the helper outside `modules/`
makes direct relative imports awkward and sensitive to relocating the consumer.
`self.data` provides a stable flake-root-relative route to those files instead.

Keep large configuration blobs, scripts in their native language, and value-only
Nix expressions in `data/`, mirroring the consuming feature or program when
useful. Extend `self.data.vars` for genuinely shared normalized values rather
than repeating parsing logic. Do not move credentials into `data/`; it is
ordinary flake source, not secret storage.

Prefer this interface over scattered `${self}/data/...` paths or repeated
`builtins.readFile`/JSON parsing. It also keeps value-only `.nix` files out of
the auto-imported module tree.

Nix evaluates the Git-backed flake source, so new untracked files can be
invisible during flake evaluation. Do not stage unrelated files as a workaround;
use validation that respects the current index, or explain when a new file must
be tracked.

## Hosts and user environments

`modules/host-plumbing/registry.nix` turns `host.<name>` declarations into
`nixosConfigurations.<name>` and, when enabled, deployment or ISO apps. Each
NixOS host receives a read-only `hostIdentity` containing `name`, `description`,
`primaryUser`, and `stateVersion`. Use it instead of repeating host metadata.
The registry also derives the host name, platform, and NixOS/Home Manager state
version defaults.

Treat `stateVersion` as compatibility metadata. Never advance it merely because
Nixpkgs or Home Manager changed.

Home Manager environments are attached at
`host.<name>.userEnvironment.<username>` and combine:

1. Home Manager modules contributed by imported host features.
2. The selected `homeProfile`.
3. Optional `userPreferences`.
4. Host-user attachment modules.

`integrated` mode activates through NixOS; `standalone` mode exposes
`homeConfigurations."<user>@<host>"`. Both modes must consume the same module
graph. Shared modules must therefore avoid integrated-only arguments such as
`osConfig`; use the Home Manager `userEnvironment` identity when host context is
needed.

A reusable NixOS feature contributes user configuration through:

```nix
userEnvironment.sharedModules = [ homeModule ];
```

It must not configure `home-manager.users` directly—the registry owns activation
and attachment. Contributions are evaluated only when the host imports the
feature and has a user environment.

## Generated files and documentation

`flake.nix` is generated. Declare inputs through `flake-file.inputs` in an
appropriate module, then run:

```sh
timeout 120s nix run .#write-flake
timeout 120s nix flake lock          # only when inputs changed
timeout 120s nix build .#checks.x86_64-linux.check-flake-file --no-link
```

Never hand-edit `flake.nix` to satisfy the check.

Subdirectory `README.md` files are generated from `/** ... */` docstrings. Keep
the docstrings accurate, but do not run the destructive `mkflakedocs`
regeneration unless requested. Put durable architecture guidance under `docs/`
instead of duplicating it in generated READMEs or this file.

## Scope and validation

`modules/host/cryptid.nix` is unusually large and script-heavy. Do not read,
reformat, deeply evaluate, or modify it unless the task concerns cryptid or
genuinely affects every host. Prefer evaluating the relevant host.

Start with syntax/whitespace and the narrowest affected output, using timeouts:

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

Run only the checks relevant to the change. Do not claim a check passed unless it
actually ran successfully; if broader validation would pull in an unrelated
large host, state the focused validation boundary.
