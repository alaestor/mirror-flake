# Alloy WAL completion patch scope

## Conclusion

The local fix touching **two production Go files** built successfully against
Alloy v1.21.3 and passed the original overlapping-outage VM reproducer. The
unpatched control recovered none of the 12 queued entries; the patched run
recovered all 12, with source journals removed in both tests. It also passed the
simultaneous server/client shutdown case. Production remains unchanged.

The patch changes no WAL or checkpoint format, writer, HTTP sender,
configuration schema, or Prometheus dependency. This validates the proposed fix
for the reproduced failure, not every WAL failure or an upgrade from existing
unsafe checkpoints.

The smaller approach is to keep the newest segment observed by each endpoint's
reader unmarked. Reader progress into a later segment is the existing ordering
boundary that makes an earlier segment eligible for completion. Adding explicit
writer-to-tracker segment-closure callbacks is unnecessary for that approach.
It deliberately checkpoints conservatively rather than immediately marking every
closed segment.

## Code examined

The deployed baseline is Alloy v1.21.3. The relevant code is its
[tracker](https://github.com/grafana/alloy/blob/v1.21.3/internal/component/common/loki/client/internal/marker/tracker.go),
[watcher](https://github.com/grafana/alloy/blob/v1.21.3/internal/component/common/loki/wal/watcher.go),
and [endpoint adapter](https://github.com/grafana/alloy/blob/v1.21.3/internal/component/common/loki/client/consumer_wal.go).
The adapter registers each segment's queued entries before the watcher proceeds
to the next segment. The watcher processes segments serially. The sender can
finish individual batches before the watcher has finished reading the segment.

The pinned [Prometheus WAL implementation](https://github.com/grafana/prometheus/blob/6ac45be9754c/tsdb/wlog/wlog.go)
flushes the old segment before creating a successor and switches the write head
under its write mutex. Opening existing WAL storage creates a new segment with
index `last + 1`; it does not append to the previous process's final segment.

Upstream was also checked at commit
[`c3e1ae85`](https://github.com/grafana/alloy/tree/c3e1ae85298ba073c112115a692f8f458a5bcb56).
Its tracker moved from `client/internal/marker/` to `client/internal/savepoint/`
and checkpoint APIs changed, but the completion algorithm and newest-segment
startup fallback remain materially unchanged. A patch pinned to v1.21.3 would
already need a path/API rebase onto this newer source, not an algorithm redesign.

## Smallest conservative design

The tracker already sorts its per-segment in-flight counts before selecting a
completed prefix. Stop that scan before the newest tracked segment, retaining
its tracking entry even when its count is zero or it has aged out. An older
segment remains subject to the existing count and retention rules.

Conceptually:

```go
for i, item := range orderedSegmentCounts {
    if i == len(orderedSegmentCounts)-1 {
        break // Keep this reader's newest observed segment unmarked.
    }
    // Existing zero-count/expiry and completed-prefix logic follows.
}
```

Retaining that newest entry is essential. Merely refusing to persist its marker
while deleting its tracking entry would lose the ordering boundary.

A companion watcher change must make **the oldest retained segment** the startup
fallback when there is no usable checkpoint. Otherwise, a first segment that is
correctly left unmarked would still be skipped after restart creates a new head.
Keep the normal strictly-after-checkpoint resume rule for checkpoints produced
under the corrected invariant.

The patch applies cleanly to the pinned source and adds roughly ten
production lines, mostly comments. The telemetry feature applies it as a
temporary bugfix, guarded against an Alloy version change. Upgrade handling still needs validation before
production activation.

| File below `internal/component/common/loki/` | Change or coverage |
| --- | --- |
| `client/internal/marker/tracker.go` | Retain and exclude the newest tracked segment from completion. Newer upstream uses `savepoint/tracker.go`. |
| `wal/watcher.go` | Start at the earliest retained segment without a usable checkpoint. |
| `client/internal/marker/tracker_test.go` | Update completion expectations and cover open-segment reuse, expiry, and acknowledgment ordering. |
| `wal/watcher_test.go` | Replace the existing expectation that an invalid marker skips old segments; test missing/stale markers and an empty new head. |
| `client/consumer_wal_test.go` | Existing tests run unchanged; the VM test covers warm-up, outage, restart, and replay through the real chain. A dedicated new consumer regression remains future work. |

No new interface methods or mocks are required. Most maintenance work is in the
regressions and upgrade handling rather than the production guard.

## Why checking the writer head alone is insufficient

Rotation proves that no more writes belong to the old segment. It does not prove
that the reader has registered every entry already in it. For example:

1. A warm-up entry is sent; the tracker count for segment 0 reaches zero.
2. Another entry is written to segment 0 but not yet read.
3. The writer rotates to segment 1.
4. A tracker that checks only `segment < writerHead` can now mark segment 0.

The reader-progress guard waits until the reader moves beyond segment 0, after
registering its remaining entries. Their in-flight counts then prevent marking
until they are resolved under the existing sender policy.

A small scheduling model enumerated 237 valid orderings of writes, reads,
acknowledgments, and rotation. The original rule had 69 unsafe schedules, a
writer-head-only guard had 54, and retaining the newest observed segment had
none. This model excludes corruption, expiry, process failure, and actual Go
channel behavior. It checks the proposed ordering argument, not Alloy's complete
implementation. The model and sketch are disposable files under
`__reference/alloy-patch-study/`, not committed package sources.

## Costs and remaining decisions

- Healthy low-volume clients keep their current segment uncheckpointed until
  their reader observes a later segment. Restarts can replay already delivered
  entries from that segment. Default segments are 128 MiB; this is not a strict
  total replay bound when older segments also have pending entries. Loki's
  deduplication must not be treated as exactly-once transport. The existing
  tracker checks its timer only when a data event wakes it. Observing a newer
  segment therefore need not immediately checkpoint an eligible older one;
  another event may be needed. The prototype leaves that scheduling behavior
  unchanged.
- Old checkpoints may already mark an unsafe segment. The new invariant cannot
  repair that retrospectively. Plan a backed-up, one-time conservative replay of
  the last marked segment or retained WAL. Do not discard the WAL. Seamless,
  automatic legacy-state repair would add migration work beyond the two-file fix.
- Queue-drop policies, age-based cleanup, and corrupt-segment handling can still
  discard entries. This feature disables finite retry exhaustion, but that is
  separate from the patch. This patch prevents premature
  completion of an active segment; it does not promise durable delivery through
  every failure. In particular, the watcher currently advances past some corrupt
  or short replay segments with warnings. Strict fail-closed behavior there is a
  separate policy change.
- If prompt checkpointing of the final closed segment matters, add an explicit
  reader-completion event instead. The watcher must emit it only after a known
  immutable segment is fully read, never on cancellation or a truncated read.
  Forward it through the endpoint adapter into the tracker's existing event
  channel. That touches three production files plus tests and no format change,
  but introduces an interface/event-ordering contract to maintain. A writer-only
  closure notification still does not solve the unread-entry race above.

## Runtime experiment

The initial scratch package overrode nixpkgs `grafana-alloy` v1.21.3 without
changing its source pin or dependencies. The full binary built and passed its
version check. The same two-file fix now lives at
[`alloy-wal-completion.patch`](../../data/features/telemetry/alloy-wal-completion.patch)
and is applied inline by the telemetry feature. There is no standalone package
output or alpkgs change. Focused Go tests apply
[regressions.patch](../../tests/telemetry/alloy/regressions.patch) to the pinned
upstream tests rather than maintaining copies of entire test files.

The A/B test imports the Alloy runtime/outage test from commit `c32d3a79` and
changes only the service package and endpoint retry setting. Both variants use
`max_backoff_retries = 0` so retry exhaustion cannot explain the difference.
Each test starts fresh VMs and state. The queued batch is confirmed in the WAL,
then removed from the disposable source journal before restarting the client
while the collector remains offline.

| Variant | Queued batch after collector returns | Result |
| --- | --- | --- |
| Unpatched Alloy v1.21.3, unlimited retries | 0/12 | Missing-entry assertion timed out after 120 seconds. |
| Patched Alloy v1.21.3, unlimited retries | 12/12 distinct entries | Full VM script passed in 214 seconds. |
| Patched Alloy v1.21.3, original retry defaults | 12/12 distinct entries | Independent full VM script passed in 237 seconds. |

Both patched runs also recovered all 12 entries emitted after the client booted
without its collector, preserved prior cursor/history checks, and passed the
simultaneous shutdown and subsequent fresh-ingestion batches. Metrics, tailnet
interface recreation, backend privacy, Grafana authentication, dashboard
provisioning, and alert-rule health passed in both scripts. No visible fixture
duplicates is not an exactly-once guarantee.

Race-enabled Go tests passed for the complete marker, WAL, and Loki client
packages with `go test -race -count=1 -timeout=180s`. The test changes
retain the existing coverage while replacing expectations that the newest
segment is markable or that markerless startup skips retained segments. New
regressions cover a zero-count segment receiving more entries, pending older
entries across rotation, newest-segment expiry, and acknowledgment arriving
before receive registration. Watcher assertions check every retained/new line,
not only counts.

The initial scratch test run failed two expectations: one still assumed newest-only
startup, and another assumed new-segment registration immediately triggers a
checkpoint scan. Updating those expectations and sending the newer segment's
completion event made the focused suite pass without further production changes.
The existing client tests were run unchanged; a dedicated new consumer-level
regression remains future work. The VM test exercises that chain end to end.

One later integration build failed the unchanged upstream
`TestEndpoint/batch_log_entries_separately_when_the_batch_wait_time_is_reached`.
It uses a no-op tracker, a 700 ms inter-entry sleep, and expects two HTTP batches.
Both entries arrived in one batch during overlapping builds. The marker and WAL
suites passed in that run; the complete focused race suite passed on the next
run without changing the assertion or production patch. This is evidence of a
timing-sensitive batching test, not a reproduced WAL-loss regression. Keep the
failure visible rather than adding an automatic retry or skipping the test.

Local evidence logs are `/tmp/alloy-patched-package.log`,
`/tmp/alloy-patched-control.log`, `/tmp/alloy-patched-runtime.log`, and
`/tmp/alloy-patched-unit-verified.log`. The default-retry rerun is recorded in
`/tmp/alloy-patched-default.log`.

## Validation and maintenance judgment

The integrated default three-VM check passed in 312 seconds with the in-flake
patch and push-only collector proxy. It retained the original outage assertions
and added backend-acknowledgment checks and abrupt server/client power loss after
synchronization. All 12 entries in each recovery batch were searchable; outage
and crash cases removed the disposable source journal to require WAL replay.
The focused configuration/Tailscale checks and race-enabled Go suites passed.
Lanser's complete system build and APC/Armatus system evaluations also passed.
This is local validation, not a production rollout or an exactly-once proof.
The integrated logs are `/tmp/telemetry-alloy-main-checks.log` and
`/tmp/telemetry-alloy-go-final.log`.

Before shipping, add targeted cancellation, rotation/multiple-segment, and
legacy-state upgrade cases. The initial A/B tests used clean shutdowns; the
integrated check also covers abrupt VM power loss after synchronization.
Neither covers unsynchronized writes, long retention, or disk exhaustion.
All use fresh patched state and do not demonstrate automatic recovery of entries
hidden by an old unsafe checkpoint.

Mechanically this is a small downstream patch. The behavioral maintenance burden
is moderate because it changes checkpoint timing, first-start replay policy, and
upgrade assumptions. Keep it local to the Loki WAL code and upstream it if
pursued. At each Alloy update, check patch application, these focused tests, and
the outage reproducer. Do not expand it into a custom WAL or a new checkpoint
format just to eliminate replay duplicates. The temporary bugfix belongs beside
its telemetry consumer; reconsider a separate package only if the patch grows
beyond that purpose.
