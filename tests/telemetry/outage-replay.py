

# Mandatory regression for the queued-log loss observed with Alloy.
def assert_recovered() -> None:
    collector.wait_for_unit("grafana.service")
    collector.wait_until_succeeds("curl -fsS http://127.0.0.1:3101/ready")
    sender.wait_until_succeeds("curl -fsS http://collector:3100/ready")
    collector.wait_until_succeeds(
        "curl -fsSG http://127.0.0.1:9090/api/v1/query"
        + " --data-urlencode 'query=up{job=\"node\",host=\"sender\"}'"
        + " | jq -e '.data.result[0].value[1] == \"1\"'"
    )
    collector.wait_until_succeeds(
        rules + " | jq -e '[.data.groups[].rules[]] | length == 5 and all(.[]; .health == \"ok\")'",
        timeout=180,
    )
    collector.succeed(api + "/api/search | jq -e 'any(.[]; .uid == \"telemetry-fleet\")'")


with subtest("server outage and client restart replay queued logs"):
    collector.shutdown()
    emit_recovery_batch("telemetry-outage-recovery")
    sender.wait_until_succeeds(
        "grep -a -r -F -q telemetry-outage-recovery-12 /var/lib/alloy/data-alloy/loki.write.central/wal",
        timeout=30,
    )
    # Remove this disposable VM's source copy. Recovery must replay the WAL,
    # not accidentally pass by rereading the same entries from the journal.
    sender.succeed("journalctl --rotate; journalctl --vacuum-time=1us")
    sender.fail("journalctl -t telemetry-recovery -o cat --no-pager | grep -F telemetry-outage-recovery-")
    sender.shutdown()
    sender.start()
    sender.wait_for_unit("alloy.service")
    sender.wait_for_unit("telemetry-metrics.socket")
    emit_recovery_batch("telemetry-offline-client-boot")
    collector.start()
    assert_recovered()
    assert_recovery_batch("telemetry-outage-recovery")
    assert_recovery_batch("telemetry-offline-client-boot")
    assert_recovery_batch("telemetry-cursor-recovery")
    collector.wait_until_succeeds("curl -fsSG http://127.0.0.1:3101/loki/api/v1/query_range --data-urlencode query=" + history_query + " | jq -e '.data.result | length > 0'")

with subtest("simultaneous shutdown recovers without operator intervention"):
    sender.succeed("systemctl stop alloy")
    emit_recovery_batch("telemetry-both-recovery")
    sender.shutdown()
    collector.shutdown()
    collector.start()
    sender.start()
    assert_recovered()
    assert_recovery_batch("telemetry-both-recovery")
    emit_recovery_batch("telemetry-after-recovery")
    assert_recovery_batch("telemetry-after-recovery")

with subtest("power loss replays synchronized client queue and server state"):
    emit_recovery_batch("telemetry-before-crash")
    assert_recovery_batch("telemetry-before-crash")
    collector.succeed("sync")
    collector.crash()
    emit_recovery_batch("telemetry-crash-queue")
    sender.wait_until_succeeds(
        "grep -a -r -F -q telemetry-crash-queue-12 /var/lib/alloy/data-alloy/loki.write.central/wal", timeout=30
    )
    # This case synchronizes queued WAL data before the crash. It deliberately
    # excludes loss before the first synchronization.
    sender.sleep(2)
    sender.succeed("journalctl --rotate; journalctl --vacuum-time=1us")
    sender.fail("journalctl -t telemetry-recovery -o cat --no-pager | grep -F telemetry-crash-queue-")
    sender.succeed("sync")
    sender.crash()
    sender.start()
    sender.wait_for_unit("alloy.service")
    collector.start()
    assert_recovered()
    assert_recovery_batch("telemetry-crash-queue")
    assert_recovery_batch("telemetry-before-crash")
    emit_recovery_batch("telemetry-after-crash")
    assert_recovery_batch("telemetry-after-crash")
