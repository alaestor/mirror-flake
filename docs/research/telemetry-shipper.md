# Telemetry shipper decision

The implementation keeps Alloy with a temporary in-flake WAL completion patch.
Vector was a working alternative, not a failed experiment. Its implementation
and original investigation history remain on `feat/telemetry-vector`; it is not
used on `main`. No alpkgs package or standalone package output is required.
Production activation of the new fix remains pending.

Patched Alloy preserves the existing client configuration, journal cursor, and
WAL formats, while avoiding a shipper migration. The local patch is small enough
to maintain with an explicit version guard and regression tests. It delays
checkpoints and can replay entries. Unsafe checkpoints from unpatched Alloy
still need a backed-up, one-time migration before deployment. The choice is
about the smaller operational change, not a claim that Alloy is faster or more
durable than Vector. No comparative performance benchmark was run.

## Why unpatched Alloy was insufficient

Alloy 1.21.3 failed an isolated collector-outage/client-restart test twice.
The observed sequence was:

1. A healthy client had already sent logs successfully.
2. The collector shut down and remained unavailable.
3. The client generated 12 new fixture entries. The last fixture was confirmed
   in the on-disk WAL.
4. The client shut down cleanly and booted while the collector was still offline.
5. The collector returned. None of the 12 entries appeared in Loki, although
   services, metrics, authentication, and alert-rule health recovered normally.

The stricter run rotated and vacuumed the disposable client's source journal
between steps 3 and 4, proving journal replay could not substitute for WAL
recovery. Journal deletion is a diagnostic step, not a demonstrated prerequisite
for the bug. Unlimited retries did not fix the case. These were short outages,
not disk exhaustion or the configured 24-hour expiry. This does not establish
that every reboot, a collector-only outage, or every service-only restart loses
logs. The original Alloy implementation and opt-in reproducer remain in commit
`c32d3a79` on the preserved feature branch. The corrected mainline test makes
outage recovery mandatory.

Source inspection suggests that the segment marker can advance while a WAL
segment is still writable, then skip later unsent entries on restart. This is a
mechanism supported by the local A/B test, not a claim of upstream confirmation.
The relevant pinned code is
[the marker tracker](https://github.com/grafana/alloy/blob/v1.21.3/internal/component/common/loki/client/internal/marker/tracker.go)
and [WAL watcher](https://github.com/grafana/alloy/blob/v1.21.3/internal/component/common/loki/wal/watcher.go).
The two-file patch subsequently passed the original failure reproducer
against a failing unpatched control. This supports the proposed cause and fix;
it is not a complete audit of Alloy's delivery semantics.

## Related upstream reports

During the investigation, a brief public issue/PR search found a close match in
[issue #7112](https://github.com/grafana/alloy/issues/7112), then open. Its
reproduction acknowledges a warm-up batch, confirms the segment marker, queues a new entry in
that same open segment during a Loki outage, then kills Alloy. After restart the
watcher skips the old segment and the entry is missing. It uses SIGKILL, unlike
our clean client shutdown, and therefore avoids shutdown-draining ambiguity.
An [additional reproduction](https://github.com/grafana/alloy/issues/7112#issuecomment-6384427387)
reports the same skip with unsent entries still in the old segment. These reports
corroborate the hypothesis; they do not prove our test hit precisely that path.

[Issue #7065](https://github.com/grafana/alloy/issues/7065) concerns marker
advancement when shutdown cancels pending requests. Merged
[PR #7113](https://github.com/grafana/alloy/pull/7113) avoids reporting those
canceled requests as sent. That protection is already present in the pinned
source inspected here, so it is not a missing patch we can simply enable.

[PR #7200](https://github.com/grafana/alloy/pull/7200) is also merged. It fixes
[shared markers across multiple endpoints](https://github.com/grafana/alloy/issues/6154)
using per-endpoint savepoints, not the still-writable-segment completion rule.
Our writer has one endpoint. The additional #7112 reproduction explicitly
reports that the relevant decisions remained unchanged in its source-only check
after #7200. This brief search found no PR referencing #7112; that is not proof
that no unlinked fix exists.

## Alloy patch assessment

The deeper [completion-patch investigation](alloy-wal-completion.md) found a
smaller conservative design than explicit writer/tracker closure callbacks.
Retain the newest segment observed by each endpoint's reader, never marking it
complete until that reader progresses to a later segment. Pair that with replay
from the oldest retained segment when no usable checkpoint exists.

The prototype changes two production Go files without a format change or new
interface. The trade-offs are delayed checkpoints, replayed entries on restart,
and one-time handling of unsafe legacy checkpoints.
An explicit reader-completion event is a broader alternative if prompt final
segment checkpointing matters. Writer closure alone does not prove the reader
has accounted for every entry.

The patched binary built and recovered 12/12 queued entries in the original
three-VM failure scenario, versus 0/12 for the unpatched control. Both used
unlimited retries and removed the disposable source journal before client
restart. A second patched run passed with the original retry defaults. Both
patched scripts also passed simultaneous shutdown recovery. See the
linked investigation for validation boundaries and remaining upgrade work.
Existing drop/retention policies remain separate loss cases. The feature applies
the temporary patch directly to its Alloy service package and enables unlimited
retries for retryable responses. The test check runs the actual override through
race-enabled marker, WAL, and client suites. See
[the telemetry contract](../telemetry.md) for deployment and legacy-state limits.

## Rejected alternative: Vector

Vector is FOSS under the
[Mozilla Public License 2.0](https://github.com/vectordotdev/vector/blob/v0.61.0/LICENSE).
Vector reads journals across boots, preserves numeric priorities, and sends the
existing `host`, `job`, `unit`, and `priority` labels to Loki. Sink acknowledgments
and a byte-bounded blocking disk buffer are explicit. A separate loopback-only,
push-only Caddy proxy forwards Loki's response, without a second shipper queue.
Interface-bound systemd sockets still own tailnet exposure. Grafana login,
backend privacy, LAN denial, and existing dashboards and alert rules remain part
of the runtime contract.

The tested candidate is Vector 0.61.0. The native NixOS service validates its
configuration during builds. A 24-hour event filter limits initial journal replay
without adding `--since` to journalctl. That argument conflicts with Vector's
`--after-cursor` after restart.
The proxy must bind loopback without matching only a localhost HTTP Host header;
clients use the collector's name or address. The Vector branch covers the journal-argument trap; main retains the gateway
Host-header regression.

## Vector evidence and limits

A synthetic HTTP-503/SIGKILL probe recovered all 12 synchronized queued entries
on two runs, without visible duplicates. The final three-VM regression passed in
300 seconds with real journals, Loki, and persistent host state. All 12 entries
per fixture batch were searchable, with no visible duplicates, after overlapping collector
outage/client reboot, simultaneous clean shutdown, and abrupt power loss after
disk synchronization. The overlapping-outage and power-loss cases removed the
source journal copy before recovery to require disk-buffer replay. Those cases
ran in the Vector branch default runtime check and were retained for the
patched-Alloy integration. Loki can deduplicate identical records, so
these queries do not prove exactly-once transport.

The focused telemetry configuration and Tailscale checks passed. Lanser's full
system build and Lanser/APC/Armatus system evaluations passed too. These are
local build and VM results, not production Vector rollout verification.

Passing those cases is not a losslessness claim. Vector's disk buffer
[synchronizes every 500 milliseconds](https://vector.dev/docs/reference/configuration/sinks/loki/#buffer).
Unsynchronized writes, failed disks, full buffers followed by source rotation,
and nonretryable backend responses remain loss cases. Buffer saturation and
power loss before the first synchronization are not covered by the VM test.
Loki's acceptance limits can also reject old replayed records. Metrics missed
while offline cannot be backfilled by changing the log shipper.

## Vector costs and migration

Alloy offers tighter Grafana integration and one collector for metrics, logs,
traces, and profiles. Vector adds another configuration language and shipper to
operate, but avoids a downstream Alloy patch. Its explicit byte-bounded blocking
buffer is a real advantage; Alloy's WAL has no equivalent byte quota in this
configuration. Both candidates use the separate push-only proxy, so that process
is not a Vector-only cost.

Initial Vector enrollment scans the retained journal before discarding entries
older than the lookback, so it can cost more startup I/O than a bounded
journalctl query. Subsequent runs use the checkpoint. CPU and memory have not
been benchmarked. Neither candidate was chosen on presumed performance.

Vector cannot reuse Alloy's journal checkpoint or import its pending WAL.
A future switch would need collector-first rollout while it is available,
retained Alloy state for rollback, and acceptance of possible journal replay.
Keeping patched Alloy avoids that shipper migration, but not the unsafe legacy
checkpoint problem. See [the telemetry contract](../telemetry.md) for the current
Alloy operational limits and validation.
