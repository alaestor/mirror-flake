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

The [port plan](ports.md) specifies the shared metrics and ingestion ports so
clients and the collector agree. Each host's record sets its local backends.

Socket proxies use explicit IPv4 listeners when `networking.enableIPv6` is
false, and dual-stack listeners otherwise. Both retain device binding and the
same interface-scoped firewall rules. A dual-stack socket cannot serve as the
IPv4 listener when the kernel's IPv6 stack is disabled.

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

Fleet telemetry is Grafana's default home dashboard unless a user or organization
has selected another home dashboard. It defaults to seven days. Horizontal
solid green gauges at the top show each host's successful scrapes as a
percentage of recorded scrapes over the selected range. The unfilled remainder
represents failed scrapes. Periods without recorded scrapes are
unknown and excluded, not assumed healthy or down.
Fleet charts and the event overview sit above host rows, which repeat from
node-exporter scrape membership. New scrape members appear without adding
panels. The compact
status shows the latest scrape; its history preserves failed scrapes within
each plotted interval. Missing scrapes remain gaps, not recorded downtime.

Host rows also show CPU non-idle percentage, memory usage estimated from
available memory, and the hottest reported hardware sensor. These gauges show
values at the selected range end, not whole-range averages. Temperature may
come from a CPU, GPU, drive, or another sensor; its display scale is not a
device-specific alarm limit. Hosts without sensor metrics show no data.

The event tables summarize recurring message shapes rather than display a raw
journal. Query-time normalization replaces paths, URLs, quoted dotted names,
UUIDs, hexadecimal IDs and numbers with placeholders. Stable wording remains,
so duplicate D-Bus declarations with different names and paths form one class,
while activation failures remain separate. Records consisting entirely of
tqdm-style progress bars form an `Iteration progress output` class regardless
of bar width, counters or redraw count. Bars accompanied by other text retain
that text through ordinary normalization. Counts measure journal records, not
individual progress redraws; neither stored priority nor raw output changes.
Classes stay scoped to host, system unit, source and numeric priority. The
`systemd-coredump@` and `drkonqi-coredump-processor@` crash handlers group by
their service templates rather than their per-crash instances. Other unit
instances remain distinct. This normalization happens only in overview queries;
stored units stay intact, and Explore links include every instance in the family.
Unit filters still select original units before grouping. Source
uses the syslog identifier when available, otherwise the system unit or
`unknown`; older entries without source metadata can therefore appear
separately from newer ones.

Counts cover the selected time range, not a sample of recent log lines. Sort by
count to identify recurring noise, or filter columns to inspect a source. Click
an event family to open its original occurrences in Explore with the same time
range. Grouping is heuristic: variable values can matter diagnostically, and
differently worded messages can describe the same underlying problem. Inspect
the original messages before deciding that a class is harmless. No normalized
message or event ID is added to the index, and stored messages remain intact.

The event tables use a repository-owned Grafana panel with 100-row pages,
scrolling within each page and single-line truncated rows. Column filters and
sorting apply to the complete result before paging, so every returned family
remains reachable. **Dim family** reduces a row's contrast; **Undim family**
restores it. **Show dimmed** includes or hides dimmed rows without changing
their counts, stored logs or alerts.
Dimming matches the complete family identity, including host, system unit,
source and numeric priority. It does not follow a class onto another host or
dim a higher-priority variant. Changed family wording appears undimmed.

Dimming and the Show dimmed preference are saved per Grafana user in Grafana's
database and shared by the fleet and host tables. They survive rebuilds and
browser changes, but are not shared between users. Concurrent saves merge
against current server state; another tab refreshes its preferences when it
regains focus. If loading preferences fails, all families remain visible and
dimming controls stay disabled until retry. Failed saves leave the previous
view unchanged and display an error. Family identities are stored as user
preferences, not as journal metadata; include Grafana's database in backups.

The telemetry-server feature packages the panel from
`data/features/telemetry/event-panel/` and allows only that plugin ID to load
unsigned. Other plugin signature checks remain enabled. Its AMD entry point
uses Grafana's React and runtime APIs, without npm dependencies, a separate
backend or browser-injected scripts. Keep its storage schema versioned and
rerun the browser check when changing the panel or upgrading Grafana.

Overview controls select hosts, system units, severity and case-sensitive literal
message text. Warning and higher is the default; known noise remains visible so
its volume can be measured. A reversible filter can hide a narrowly matched Qt
message. Text and noise filters apply before grouping; Explore links open the
whole family rather than carry these two filters forward. None of these
controls changes error charts, alerts or storage. The tables use ordinary
LogQL aggregation across retained logs, not the experimental pattern ingester,
and have no minimum occurrence count. Large ranges or many distinct message
shapes can reach Loki's bounded 5,000-series query limit. This is independent of
the panel's page size: Loki evaluates the full result before browser pagination.
Raising the limit allows larger overviews at the cost of query memory and
response size, especially because each family carries an Explore query. Outer
aggregations such as `topk` can still hit an intermediate query limit and would
omit families even if they succeeded. Narrow the host, unit or time range when
the limit is reached rather than treating a failed query as an empty overview.
Error bars count non-overlapping time buckets, stacked by source, and grow wider
for longer dashboard ranges.

Loki splits both range queries and instant metric aggregations into daily jobs,
with bounded parallelism. These use separate settings. Changing only
`split_queries_by_interval` leaves instant overviews on Loki's hourly default,
creating 168 jobs for a seven-day count and risking HTTP timeouts even on a
small fixture. Keep the seven-day runtime regression when tuning query limits
or splitting.

The loopback gRPC receiver allows messages up to 32 MiB so full family vectors
can reach the query frontend. Loki's default 4 MiB transport cap cannot carry a
5,000-family result with these links, even when the series limit permits it.
Keep the transport and series budgets bounded together rather than disabling
either limit.

Use Explore with the Logs data source for LogQL searches, such as
`{job="journal",host="example",unit="example.service"}`. Labels deliberately
exclude process IDs and boot IDs to keep the index small. Priority is the
journal's numeric syslog priority, not a guess based on message text. Applications
that log everything at info will not produce priority alerts; spam alerts still
count those lines.

The indexed `unit` label remains the system unit, including the user manager
for desktop applications. Collection adds `user_unit` and `syslog_identifier`
as structured metadata when the journal provides them. Raw user-unit names can
contain instance hashes or process IDs and must not become indexed labels.
Filter metadata after a stream selector, for example
`{job="journal",host="example"} | syslog_identifier="example-app"`.
Missing source fields stay absent; kernel entries do not acquire an invented
unit.

Collection also writes `detected_level` metadata from numeric priority:
0 and 1 map to `fatal`, 2 to `critical`, 3 to `error`, 4 to `warn`, 5 and 6 to
`info`, and 7 to `debug`. Missing or invalid priority maps to `unknown`, never
message-text inference. This makes priority authoritative for consumers such
as native log patterns as well as alerts. Older entries are not rewritten;
the dashboard displays severity from their numeric priority. Message text,
journal cursors, and the delivery WAL are unchanged.

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

State stays on local disk. `fleet.logging.retentionDays` supplies the shared
maximum log age for local journals and Loki, currently one year. Local journals
rotate at least weekly and have a 15G persistent limit and 128M volatile limit;
size limits can remove history sooner. Rotation does not mean deletion after a
week. Journald owns its binary files; do not apply logrotate to them.
Ordinary file logs need their service's own rotation policy.

Loki uses its compactor for age-based deletion, not weekly journal rotation.
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
nix build .#checks.x86_64-linux.telemetry-panel --no-link
nix build .#checks.x86_64-linux.tailscale --no-link
nix build .#checks.x86_64-linux.telemetry-alloy-wal --no-link
nix build .#checks.x86_64-linux.telemetry-runtime --no-link
```

The runtime test uses a trusted interface in place of Tailscale and a second,
untrusted LAN. It checks journal ingestion, metrics scraping, backend privacy,
Grafana authentication and provisioning, interface recovery, and journal cursor
resumption after stopping and starting collection. It also checks
source metadata, all eight priority mappings, missing source fields, and native
pattern severity with deliberately contradictory message text. Metadata must
remain outside the index and survive the same outage/replay cases as messages.
The overview regression groups more than 500 changing messages, checks source
and priority isolation, preserves distinct failure wording, and verifies
selected-range counts, filters and escaped Explore links. A separate case checks
1,500 distinct normalized families in a seven-day query, exact counts and drilldown
links, so changing raw values that collapse into one family cannot mask the
series-limit regression. The panel check runs real Grafana and Chromium with
synthetic Loki responses. It exercises GUI dimming, hiding and restoring
families, persistence across fresh browser
profiles, Viewer-account isolation, pagination, global filtering and sorting,
scrolling, truncation, Explore links and visible storage failures. Query
validation alone does not verify rendering or interactive state.
The runtime test also checks gateway
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
