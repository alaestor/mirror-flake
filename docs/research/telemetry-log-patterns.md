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

The first samples came from collector services. At the same observation point,
the desktop host had no returned patterns despite continuing to deliver logs.
Warning-only queries also returned none. This proves the API works, but does
not yet establish useful coverage of desktop warning spam. Do not present an
empty patterns list as proof that no warnings occurred.

## Limits

[Grafana documents](https://grafana.com/docs/grafana/latest/visualizations/simplified-exploration/logs/patterns/)
that patterns are extracted on ingestion and are ephemeral, with a three-hour
window by default. Enabling the feature does not cluster the stored seven-day
journal retrospectively. Pattern counts are an exploration aid, not an exact
replacement for raw-log counts or alert evaluation.

The [Loki 3.7.9 Drain implementation](https://github.com/grafana/loki/blob/v3.7.9/pkg/pattern/drain/drain.go)
uses a default token-similarity threshold of 0.3. It also limits cluster count
and skips messages outside its supported token counts. This is token-based
template matching, not semantic similarity. The
[pattern ingester configuration](https://github.com/grafana/loki/blob/v3.7.9/pkg/pattern/ingester.go)
does not expose that similarity threshold as a YAML option. Its volume threshold
is a different setting and must not be described as matching sensitivity.

## Collection improvements to evaluate

The current stream retains host, system unit, and numeric journal priority.
Desktop applications often share a system user-manager unit, so that unit alone
does not identify the emitting application. Evaluate collecting the journal's
user unit and syslog identifier as additional source information.
[Alloy exposes journal fields for relabeling](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/).
Verify field availability against real system and user-service entries before
choosing fallbacks.

Preserve the existing `unit` field rather than silently changing per-unit
alerts. Keep numeric priority authoritative and derive display severity from
it during collection, so Drilldown and dashboard queries agree. Retain
query-time mapping for older entries. Do not index process IDs, addresses,
message text, or discovered pattern IDs. Put high-cardinality source details
in structured metadata if needed.

## Next experiment

1. Observe fresh desktop warning bursts and compare native patterns with raw
   counts over the same interval. Check skipped messages, query pruning, and
   cluster eviction before changing limits.
2. Inspect source fields on representative desktop messages. Validate any
   additional collection stages without changing WAL or replay behavior.
3. Check whether a recent-pattern view is sufficient. If arbitrary seven-day
   grouping is required, evaluate persistent pattern summaries or a bounded
   query-time clustering service with links back to raw records. Test changing
   hexadecimal IDs, numeric counters, unrelated messages with similar prefixes,
   and interleaved sources before choosing it.

The trial plugin and pattern-ingester flag are not part of the adopted flake
dashboard. They remain experimental runtime state until coverage and resource
cost are understood.
