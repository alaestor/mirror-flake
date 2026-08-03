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
protocol's public server name. Concrete storage locations, network topology,
credentials, and one-machine exceptions remain host-owned.

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
