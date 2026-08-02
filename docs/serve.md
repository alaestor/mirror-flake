# Hosted services and domains

This flake separates local hosted-service policy from public ingress policy.
Both layers are opt-in: importing a module makes its options available but does
not start a daemon, publish a route, or open a public firewall port.

Lanser is currently the only server host and the only consumer of these modules.

## Module layers

| Layer | Path | Export prefix | Responsibility |
|---|---|---|---|
| Service | `modules/serve/services/` | `flake.modules.nixos.serve-` | Configure one opinionated local service or served artifact. |
| Domain | `modules/serve/domains/` | `flake.modules.nixos.domain-` | Curate service modules and expose enabled members through Caddy. |

Services relate to ordinary features in the same way that domains relate to a
curated feature set: a domain collects and configures related service modules,
but the host decides which members of that collection are active.

Every service module exposes `serve.<name>.enable` with `lib.mkEnableOption`.
The option defaults to `false`, and all service implementation belongs beneath
`lib.mkIf cfg.enable`. This applies to daemons such as Matrix and Jellyfin,
infrastructure such as Caddy, and served artifacts such as Cinny or a static
site.

Domain modules do not activate the services they import. Their Caddy virtual
hosts and firewall openings are conditional on the relevant service's enable
option. Consequently, importing a domain with all services at their defaults
has no externally visible effect.

Caddy is shared infrastructure rather than a member of every domain collection.
The host imports `serve-caddy` once and enables it when any domain should be
published. This avoids importing the same exported module through multiple
domain compositions.

## Host composition

A host serving a curated domain imports the domain module and explicitly enables
the desired services:

```nix
{
  host.example.modules = (with inputs.self.modules.nixos; [
    serve-caddy
    domain-example
  ]) ++ [
    {
      serve = {
        caddy.enable = true;
        example-api.enable = true;
        example-site.enable = true;
      };
    }
  ];
}
```

The domain owns public hostnames, reverse-proxy routes, TLS behavior,
authentication or challenge policy, and the ports needed for those routes. The
services own their local daemon or artifact configuration and should listen
privately by default where applicable.

A service need not belong to a domain. A host can import a `serve-*` module
directly and enable it, but then the host owns all exposure policy, including
proxy configuration and firewall rules. Lanser uses `serve-torrenting` this way
because qBittorrent is private and confined to its VPN namespace.

## Current domain sets

| Domain module | Imported services | Published names |
|---|---|---|
| `domain-0x04cc` | Static site, Matrix, Cinny, Headscale/Headplane | `0x04.cc`, `matrix.0x04.cc`, `headscale.0x04.cc` |
| `domain-remotehost` | Filebrowser, Jellyfin | `media.remotehost.cc`, `download.shota.zip`, `jellyfin.remotehost.cc`, `shota.zip` |

Each route is independent. For example, importing `domain-0x04cc` and enabling
only Headscale and Caddy publishes only the Headscale virtual host; it does not
start Matrix, build Cinny, serve the static site, or open Matrix federation port
8448.

## Configuration ownership

- Service modules provide reusable, opinionated defaults. Use `lib.mkDefault`
  where a host is expected to refine policy.
- Domain modules provide the configured public bundle: names, routes, TLS,
  authentication, and conditional firewall openings.
- Host modules select services and contain concrete network addresses, storage
  choices, hardware details, and one-host refinements.
- Large static configuration and scripts belong under `data/serve/` and are
  accessed through `self.data`.
- General machine policy remains under `modules/features/`; it should not move
  into `serve` merely because a server host consumes it.

## Adding or changing a service

1. Export the NixOS module as `flake.modules.nixos.serve-<name>`.
2. Define `serve.<name>.enable` with `lib.mkEnableOption` and guard all effects
   with it.
3. Keep the local listener private and avoid public firewall rules.
4. If it belongs to a public bundle, import it from a `domain-*` module and gate
   every corresponding route and port on its enable option.
5. Import shared proxy infrastructure once from the host, then import the domain
   or standalone service and enable the selected `serve.*` options there.
6. Validate the affected host and both enabled and disabled behavior where
   practical.

Do not put durable guidance in `modules/serve/**/README.md`; those files are
generated from module docstrings.
