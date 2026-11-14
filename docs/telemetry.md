# Fleet telemetry

Telemetry separates host collection from central storage. `telemetry` reads the
local journal with Alloy and exposes node exporter metrics, including systemd
unit state. `telemetry-server` extends that client with Loki, Prometheus, and
Grafana. The server remains a client so its own journal follows the same path.
Neither feature activates just because a host imports it. Required Grafana data
source plugins are Nix packages, not startup downloads.

The NixOS `tailnet-client` aspect enables collection by default when Tailscale is
enabled. Android does not run these collectors. `fleet.telemetry` declares the
default server, named tailnet, and explicit scrape membership. Modules consume
these facts without evaluating another host. Adding a NixOS tailnet host enables
log shipping; also add its name to scrape membership for metrics. Override
`telemetry.enable = false` to opt out of collection and remove its scrape entry.

## Network and trust

All application listeners bind loopback. Systemd socket proxies expose only
Grafana, host metrics, and a push-only log proxy on the selected interface.
`BindToDevice` restricts the sockets in the kernel, in addition to interface-only
firewall rules. Device activation starts the sockets when the VPN interface
appears and restarts them after device recreation. Activation also starts new
listeners when the VPN already exists. A missing VPN must not block
boot. No public domain route or global firewall opening belongs to these
features.

HTTP inside the encrypted tailnet does not mean public HTTP. Do not forward
these ports from a router or expose them through the public reverse proxy.
Tailnet membership and ACLs authorize ingestion and metrics access. Clients
cannot query Loki through the push endpoint, but trusted clients can submit
arbitrary labels, including
another host's name. This is operational telemetry, not tamper-proof audit
storage. Local processes can reach the loopback backends. Journal entries may
contain secrets or personal data; everyone granted Grafana access can search
all collected hosts.

Grafana requires login, disables anonymous access and signup, and generates an
initial admin password and encryption key on first startup. Neither is in the
Nix store. On the collector, retrieve the password with:

```sh
sudo cat /var/lib/grafana/initial-admin-password
```

Log in as `admin` at the configured `telemetry-server.publicUrl`, then change the
password in Grafana. The initial-password file is only a bootstrap record;
changing it later does not reset an existing account. Create Viewer accounts
for routine use. Keep the encryption key with any backup of Grafana's database.

## Search and alerts

The provisioned Fleet telemetry dashboard gives a starting view. Use Explore
with the Logs data source for LogQL searches, such as
`{job="journal",host="example",unit="example.service"}`. Labels deliberately
exclude process IDs and boot IDs to keep the index small. Priority is the
journal's numeric syslog priority, not a guess based on message text. Applications
that log everything at info will not produce priority alerts; spam alerts still
count those lines.

Grafana evaluates rules for journal errors, critical messages, per-unit spam,
failed systemd units, and low local disk space. Critical messages also match the
broader error rule. Temporarily offline laptops are not alerted on by default;
check scrape availability on the dashboard. Rules and thresholds belong in the
flake. `telemetry-server.alerts.ignoredPatterns` excludes matching RE2 line
patterns from log alert evaluation only. Use narrowly anchored patterns; the
logs remain searchable, and metric alerts are unaffected.

Alerts are an inbox for manual review, not an acknowledgment queue. Grafana
shows active alerts and stores state transitions in Loki for its alert history
view. Resolved alerts leave the active list but remain in history until log
retention expires. Silences mute notifications; they do not stop evaluation or
hide firing alerts. For persistent known noise, change the exclusion patterns
or the relevant rule instead.

A catch-all notification-policy child route is muted all day. SMTP is disabled,
and no external delivery credentials are configured. To add delivery later,
provision a real contact point, replace the muted route, and test both a firing
and resolved notification. Merely adding a contact point will not unmute the
policy. The collector cannot report its own total outage without an independent
observer.

## State and failure behavior

State stays on local disk. Loki retains logs for two weeks by default;
Prometheus retains metrics for up to 30 days or its configured size limit,
whichever expires first. Loki compaction deletes asynchronously, so retention
is not a hard disk quota. Monitor disk usage and tune retention to actual volume.
Backups to a NAS are a separate host policy, not an implicit dependency of
collection. This data is not a substitute for source-host backups.

Alloy stores journal cursors and its Loki write-ahead log in its local state
directory. The feature enables the experimental WAL explicitly and uses unlimited
HTTP retries for retryable failures. The 24-hour journal lookback and WAL segment
age are separate retention limits, not a delivery guarantee or disk quota.
Nonretryable responses, age-based cleanup, disk exhaustion, journal rotation,
and unsynchronized writes can still lose entries.

The local completion patch keeps the newest reader-observed segment
uncheckpointed and replays the oldest retained segment when no usable checkpoint
exists. This prevents the queued-entry skip reproduced with unpatched Alloy.
Healthy restarts may replay already-delivered entries. This is not exactly-once
transport. Keep the patch pinned to the tested Alloy version and rerun focused
Go and VM tests before updating it.

The push-only proxy forwards Loki's actual response rather than acknowledging
into a second shipper queue. The collector remains a single point of failure;
recoverable local queues do not make it highly available. Do not delete Alloy
state casually.

Prometheus cannot backfill scrapes missed while a host or the collector was
offline; those gaps remain after recovery. Grafana's local database holds
accounts, sessions, silences, and UI state. Provisioned rules and dashboards come
from the flake and cannot be edited persistently in the UI.

### Existing unpatched clients

Before activating the patch on an existing client, account for checkpoints
written by unpatched Alloy. Such a checkpoint may already hide unsent entries;
the patch cannot repair that retrospectively. While the collector is available,
stop Alloy, back up its complete state directory with ownership preserved, and
plan a conservative replay from the retained WAL. Preserve or rename the
endpoint's `segment_marker` instead of deleting WAL segments. Confirm the actual
state path from the running service before acting. Replaying retained entries
can produce duplicates or exceed Loki's timestamp/age acceptance limits.

Do not automate checkpoint removal on every restart. Test the one-time migration
against a copy of the affected state before production activation, then verify
new unique markers and retain the backup for rollback. The journal cursor and
WAL formats are unchanged; no Vector state migration is involved. The collector
proxy is compatible with existing Alloy clients, so deploy the collector first.
See [the shipper investigation](research/telemetry-shipper.md) for the rejected
Vector alternative and [patch validation](research/alloy-wal-completion.md).

## Validation and rollout

Run focused checks before activation:

```sh
nix build .#checks.x86_64-linux.telemetry --no-link
nix build .#checks.x86_64-linux.tailscale --no-link
nix build .#checks.x86_64-linux.telemetry-alloy-wal --no-link
nix build .#checks.x86_64-linux.telemetry-runtime --no-link
```

The runtime test uses a trusted interface in place of Tailscale and a second,
untrusted LAN. It checks journal ingestion, metrics scraping, backend privacy,
Grafana authentication and provisioning, interface recovery, and journal cursor
resumption after stopping and starting collection. It also checks gateway
method/path restrictions and acknowledgment failure when Loki is stopped,
queued-log replay after overlapping outages and client reboots, simultaneous
shutdown, and power loss after disk synchronization. Removing a disposable
source journal copy proves that queued replay does not depend on rereading it.
The tests do not cover disk exhaustion, legacy checkpoint migration, or power
loss before synchronization. They do not test Headscale enrollment, tailnet DNS,
or production ACLs. After deployment,
verify those separately, check the collector's scrape targets, send a unique
journal marker from each host, and confirm it appears in Explore. Rebuild each
client to roll out collection; updating only the collector cannot configure
other hosts.
