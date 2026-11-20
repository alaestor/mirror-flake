# Port assignments

[The port plan](../modules/fleet/ports.nix) is the source of truth for fixed
ports we provision. Add the assignment there even if it matches the daemon's
default, then pass it to the option that configures the daemon or socket. The
table is available as `fleet.ports`. Clients can read the serving host's entry
without evaluating that host's configuration.

## Where an assignment belongs

Use the serving host's name for a deployment choice. Keep network-facing and
local assignments in the same host block, with comments separating them where
useful. Use `shared` for protocol ports and choices several deployments must
agree on. Two hosts that happen to use the same number do not have to share an
assignment.

The port plan does not open a firewall or configure a listener by itself.
Addresses, interfaces, transport, network namespaces, and firewall rules stay
with the service, domain, or host that owns them. When a listener, proxy,
firewall rule, or client refers to the same endpoint, use the same entry or
read the effective service option. An external NAT port is a separate endpoint
from the daemon's bind port.

## Names and values

Use `service` for a primary listener and `service-purpose` for another endpoint.
Use an integer for one port, a list for discrete ports, or `{ from; to; }` for
an inclusive range. Match the consumer's needs instead of wrapping single ports
in lists. For example:

```nix
flake.fleet.ports.archive = {
  # Reached over the network.
  backup = 8443;
  transfer-passive = { from = 40000; to = 40009; };

  # Local listeners.
  backup-admin = 8081;
  sync-workers = [ 8201 8203 ];
};
```

Pass the host record through `hosts/<host>/default.nix` to its private
fragments. Reusable modules take ordinary typed service options. They do not
look up the current host in the table. A reusable fallback can make standalone
use or a test fixture convenient, but a deployed host must provision its fixed
listeners explicitly.

## Limits and checks

If upstream offers a supported port setting, set it explicitly. If a packaged
socket fixes the port, or an application chooses it at runtime, don't copy the
number into the plan and pretend it controls the bind. If we configure a client
or firewall for an externally managed listener, name that endpoint in the table
and keep it in sync with the external configuration. Unix sockets and internal
non-IP transports are outside the TCP/UDP port plan.

The plan does not detect collisions automatically. Before adding a listener,
check the same host block for overlapping binds in the same transport and
network namespace. Evaluate the affected configuration. For a running host,
use `ss -lntup` and check service readiness; the daemon that failed to bind
will not appear in the socket list.
