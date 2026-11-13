# Hosted services and public domains

The serving architecture separates a workload from the policy that exposes it
to the public Internet. Service modules configure local daemons or artifacts;
domain modules compose selected services into reverse-proxy routes and ingress
rules. The host chooses which compositions exist and which services are active.

The central safety property is:

> Importing a service or domain module has no runtime or public-network effect
> until the corresponding service is explicitly enabled.

## Layers and ownership

| Layer | Export | Owns |
|---|---|---|
| Service | `flake.modules.nixos.serve-<name>` | One local daemon, artifact, or shared serving component. |
| Domain | `flake.modules.nixos.domain-<name>` | A curated service set, public names, proxy routes, TLS/authentication policy, and conditional public ports. |
| Host | `host.<name>.modules` and refinements | Selection, enablement, concrete addresses, storage, secrets, and machine-specific policy. |

Service modules live under `modules/serve/services/`; domain modules live under
`modules/serve/domains/`. Both are ordinary NixOS modules exported by outer
flake-parts modules.

General machine policy remains under `modules/features/`. A module does not
belong under `serve/` merely because a server consumes it.

## Service-module contract

Every service module defines:

```nix
serve.<name>.enable = lib.mkEnableOption "...";
```

All effects are guarded by `lib.mkIf cfg.enable`. This applies equally to a
daemon, a static artifact, a package helper, and shared infrastructure such as a
reverse proxy.

A service owns its local implementation:

- package and systemd configuration;
- local listener address and port;
- service user and runtime paths;
- reusable, opinionated defaults; and
- packages or checks tightly coupled to that service.

Services should listen on loopback or another private interface by default and
must not open public firewall ports. Use `lib.mkDefault` for values that the
domain or host is expected to refine.

A simplified service looks like:

```nix
{
  flake.modules.nixos.serve-example = { config, lib, ... }:
    let cfg = config.serve.example;
    in {
      options.serve.example = {
        enable = lib.mkEnableOption "the example service";
        address = lib.mkOption { default = "127.0.0.1"; };
        port = lib.mkOption { type = lib.types.port; };
      };

      config = lib.mkIf cfg.enable {
        services.example = {
          enable = true;
          inherit (cfg) address port;
          openFirewall = false;
        };
      };
    };
}
```

## Domain-module contract

A domain module imports the service modules that it knows how to publish, but
does not enable them. It owns:

- public hostnames and aliases;
- reverse-proxy and static-file routes;
- TLS, authentication, and protocol-specific ingress policy; and
- public firewall ports required by enabled routes.

Every route, virtual host, and port must be conditional on the corresponding
`serve.<name>.enable` value. Importing a domain with every member disabled must
produce no public listener and no workload.

Domain modules may set values intrinsic to the public composition, such as a
protocol's public server name or advertised URL, guarded by the service's enable
option. Consume shared fleet facts when the same public address is used by
clients. Tailnet DNS policy, concrete storage locations, network topology,
credentials, and one-machine exceptions remain host-owned.

Storage-specific workarounds belong beside the host's storage selection.
For example, a service can default to local state and require the mount holding
its configured data root. A host placing that state on a NAS owns additional
NAS shutdown ordering and any SSH key-loading workaround that storage requires.
Importing a NAS module alone must not change the service's storage placement.

Name a domain module after the site or property it composes, not its TLD.
`domain-0x04`, not `domain-0x04cc`. The TLD already lives in the module's
`domain` value, and a name that bakes it in goes stale the moment a domain
moves TLDs, or never fit in the first place: `domain-remotehost` serves both
`remotehost.cc` and `shota.zip`, so there was never one TLD to encode. A
service module scoped to one domain follows the same rule, e.g.
`serve-static-site-0x04` for the static site under `domain-0x04`, plain
`serve-static-site-<name>` again for any other site added later.

## Shared proxy infrastructure

The reverse proxy is shared infrastructure, not a transitive member of every
domain. A host imports it once, then imports any number of domains:

```nix
{
  host.example.modules = (with inputs.self.modules.nixos; [
    serve-caddy
    domain-example
  ]) ++ [
    {
      serve.caddy.enable = true;
      serve.example.enable = true;
    }
  ];
}
```

This avoids repeatedly importing the same exported module through independent
domain graphs and makes ownership of the public listener explicit.

### Plugin source updates

Caddy's plugin source hash depends on both the pinned Caddy version and the
plugin set. The Nushell `nup` helper updates the lockfile, then builds the
configured proxy's source bundle. If that derivation reports a hash mismatch,
the helper updates `data/serve/caddy/source.json` and rebuilds the source to
verify it. It does not compile Caddy or rebuild the host.

Other failures leave the hash unchanged. A failed verification restores the
previous hash but retains the updated lockfile for diagnosis. Review the hash
change together with `flake.lock`; accepting a reported hash is an explicit
dependency update, not an independent authenticity check. After changing the
plugin list, run `nup-refresh-caddy` from the flake root to refresh its hash
without updating inputs.

## Standalone and private services

A host may import `serve-<name>` directly without a domain. This is appropriate
for LAN-only applications, VPN-confined workloads, or services exposed by some
other mechanism. In that case the host owns all ingress policy: interfaces,
firewall rules, proxying, authentication, and reachability.

The absence of a domain module does not permit a service module to expose itself
publicly by default.

## Data and secrets

Large static files and scripts belong under `data/serve/` and are reached through
`self.data`; they should not be embedded into a module solely to avoid a separate
file. Credentials and secret runtime files do not belong in `data/` or literal
Nix configuration. Their encrypted metadata belongs behind `self.secrets`, and
the consuming host or service owns deployment to a runtime path.

### Read-only downloads

`serve-dufs` exposes named shares inside a private filesystem root. All accounts
see the same shares; host paths outside that root are unavailable to the daemon.
The Nix store is bound read-only for the executable and its dependencies. The
service cannot write to the media, and does not follow symlinks outside its
served root. Adding a library requires an explicit share definition.

Accounts belong in a required runtime environment file, normally an agenix
secret. Define `DUFS_AUTH='reader:HASH@/:ro'`, where `HASH` is the complete
SHA-512 crypt output from `openssl passwd -6`. Separate additional account rules
with `|`. The startup guard rejects missing authentication, plaintext passwords,
anonymous rules, and write permissions. Dufs checks authentication before media
listings, search, downloads, and folder archives. Basic authentication requires
HTTPS at the reverse proxy; the daemon listens only on loopback.

To change an account, edit and encrypt the secret, then rebuild the host. Hosts
must add the encrypted payload's hash to the unit's `restartTriggers`, since an
unchanged runtime secret path alone does not restart a service after rotation.
Never put plaintext account data or hashes directly in Nix configuration.

## Extension checklist

When adding a service:

1. Export it as `flake.modules.nixos.serve-<name>`.
2. Define `serve.<name>.enable` with `lib.mkEnableOption`.
3. Guard every effect with the enable option.
4. Keep listeners private and public firewall rules absent.
5. Expose typed options for values that domains or hosts legitimately refine.
6. Put native-language data and scripts under `data/serve/`.
7. Add focused checks for service-specific helpers where practical.

When adding it to a domain:

1. Import the service module without enabling it.
2. Gate each public route and port on that service's enable option.
3. Keep public protocol policy in the domain and machine facts in the host.
4. Verify both disabled behavior and the intended enabled combinations.

Validate at least the affected host evaluation. Where practical, test a minimal
module evaluation with the service disabled and enabled; the disabled case is a
security contract, not merely a convenience.

Subdirectory `README.md` files are generated from Nix docstrings. Update the
module docstring when its local interface changes, and keep durable architecture
guidance in this document.
