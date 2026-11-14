# Journal similarity grouping

## Dashboard follow-up

- Add history charts alongside the per-host CPU, RAM, and temperature gauges,
  using the dashboard time selector. Keep gauge readings at the range end
  distinct from the history and label CPU's rate interval.

## Direction

Keep Alloy's journal reader and delivery WAL. Similarity grouping belongs on
the collector, alongside the raw journal, rather than replacing log delivery
or discarding duplicates at the source. The existing dashboard remains the
seven-day health and journal view. Trial Loki's native pattern ingester through
Logs Drilldown before building a separate clustering service.

## What the trial established

The live trial used Loki 3.7.9 and Logs Drilldown 3.1.0 with Grafana 13.3.0.
Both backends restarted successfully with temporary runtime overrides. The
patterns API returned templates with changing values replaced by `<_>` and
time-bucketed counts. Thus native grouping handles differences within messages,
not just adjacent exact duplicates.

The first samples came from collector services. A later read-only observation
on November 14, 2026, around 20:04 UTC established desktop coverage too:

- A three-hour desktop warning query returned the Qt template with 120 samples.
  The raw journal contained exactly 120 matching entries since pattern ingestion
  started. Earlier entries in the same burst remained raw-only.
- A one-hour desktop query returned no patterns despite 80 raw entries,
  including five priority-3 kernel errors. The patterns query increased the
  pruning counter by 45 and the retained counter by zero. Restricting it to
  warnings and higher pruned two patterns and retained none.
- The Qt template's level was `unknown` despite journal priority 4. Numeric
  priority filtering still found it because priority is a stream label.

This confirms grouping of a desktop warning burst, but also shows why an empty
patterns list cannot establish that no warnings occurred. Browser interaction
remains untested; the API confirms Logs Drilldown is enabled and signed.

## Limits

[Grafana documents](https://grafana.com/docs/grafana/latest/visualizations/simplified-exploration/logs/patterns/)
that patterns are extracted on ingestion and are ephemeral, with a three-hour
window by default. Enabling the feature does not cluster the stored seven-day
journal retrospectively. Pattern counts are an exploration aid, not an exact
replacement for raw-log counts or alert evaluation.

The [Loki 3.7.9 patterns querier](https://github.com/grafana/loki/blob/v3.7.9/pkg/pattern/ingester_querier.go)
hardcodes a minimum of 30 samples per returned pattern in the requested
interval, then caps the result at 300 patterns. Low-volume patterns can be
learned but hidden by query pruning. Changing the query window can therefore
change which templates appear. Neither a higher volume threshold nor a
different Drain similarity threshold removes this query-time floor.

The [Loki 3.7.9 Drain implementation](https://github.com/grafana/loki/blob/v3.7.9/pkg/pattern/drain/drain.go)
uses a default token-similarity threshold of 0.3. It also limits cluster count
and skips messages outside its supported token counts. This is token-based
template matching, not semantic similarity. The
[pattern ingester configuration](https://github.com/grafana/loki/blob/v3.7.9/pkg/pattern/ingester.go)
does not expose that similarity threshold as a YAML option. Its volume threshold
is a different setting and must not be described as matching sensitivity.

## Collection source fields and severity

The collection pipeline retains host, system unit, and numeric journal priority.
Desktop applications often share a system user-manager unit, so that unit alone
does not identify the emitting application. It now carries the journal's user
unit and syslog identifier as structured metadata rather than indexed labels.
[Alloy exposes journal fields for relabeling](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/).
The relabel stage preserves these fields temporarily; the processing stage
moves them into metadata before delivery. See the
[collection contract](../telemetry.md#search-and-alerts) for names and mapping.

The desktop's three-hour sample contained 929 journal entries, including 760
with a user unit across 11 distinct user units. All 929 had a syslog identifier.
User-service entries retained `user@1000.service` as their system unit, while
the user unit distinguished applications. Some application user units contained
instance hashes or process IDs; preserve those raw names as structured metadata,
not indexed labels. Kernel errors had no system or user unit but did identify
themselves through `SYSLOG_IDENTIFIER=kernel`. Collector system-service samples
had system units and syslog identifiers without user units. These observations
support adding source information without replacing the existing unit label;
they do not establish universal field availability.

The pipeline preserves the existing `unit` field rather than changing per-unit
alerts. It derives `detected_level` metadata from numeric priority without
parsing message text. Missing or invalid priority maps to `unknown`. The
dashboard retains query-time mapping for older entries. The journal reader,
cursor, raw message text, and write-ahead log configuration are unchanged.

The [pattern stream reader](https://github.com/grafana/loki/blob/v3.7.9/pkg/pattern/stream.go)
uses structured metadata named
[`detected_level`](https://github.com/grafana/loki/blob/v3.7.9/pkg/util/constants/levels.go)
for its severity buckets. Merely adding a display label at dashboard query time
cannot correct pattern severity. The runtime test exercises the collection
pipeline through Loki and native patterns, including messages whose claimed
severity contradicts their journal priority. It also checks missing fields,
kernel and user-service entries, index exclusion, and metadata replay.

The disposable VM also grouped 40 messages with changing counters into one
template labeled `warn`, despite `level=error` in every message. During the
following gateway test, Loki reached systemd's 90-second stop timeout and was
killed. The experimental pattern ingester was enabled in this run; this does
not establish that it caused the shutdown delay or that shutdown was clean.
The full runtime suite passed, including cursor resumption, WAL-only replay
after source-journal removal, simultaneous shutdown, and synchronized power
loss. Collection configuration validation and the collector host evaluation
also passed. After activation on both hosts, live queries confirmed fresh
source metadata and priority-derived severity without indexed metadata fields.
Desktop user-service logs retained the system user-manager unit alongside
their application user unit. The temporary pattern-ingester process survived
the rebuild, but its flag remains absent from the configured service command.

## Next experiment

1. Exercise Logs Drilldown in a browser, including a known warning burst and a
   sparse interval with raw warnings but no returned patterns. Keep the raw
   journal accessible beside grouping.
2. Compare template counts for a fresh burst containing changing values, not
   just repeated exact messages. Measure resource cost against a baseline
   before adoption; one running-process memory reading cannot attribute cost
   to pattern ingestion. Compare shutdown behavior with and without the
   experimental ingester before adopting it.
3. Check whether a recent-pattern view is sufficient. If arbitrary seven-day
   grouping is required, evaluate persistent pattern summaries or a bounded
   query-time clustering service with links back to raw records. Test changing
   hexadecimal IDs, numeric counters, unrelated messages with similar prefixes,
   and interleaved sources before choosing it.

The trial plugin and pattern-ingester flag are not part of the adopted flake
dashboard. They remain experimental runtime state until coverage and resource
cost are understood.
