import json
import shlex

start_all()
collector.wait_for_unit("multi-user.target")
sender.wait_for_unit("multi-user.target")
for unit in ["loki", "alloy", "telemetry-ingress", "grafana", "prometheus", "telemetry-logs.socket", "telemetry-grafana.socket"]:
    collector.wait_for_unit(unit if unit.endswith(".socket") else unit + ".service")
sender.wait_for_unit("telemetry-metrics.socket")
collector.wait_until_succeeds("curl -fsS http://127.0.0.1:3101/ready")
sender.wait_until_succeeds("curl -fsS http://collector:3100/ready")

with subtest("application listeners remain on loopback"):
    collector.succeed("ss -ltnpH | grep -E '\"(alloy|caddy|loki|prometheus|grafana|node_exporter)\"' | awk '$4 !~ /^127[.]0[.]0[.]1:/ {bad=1; print} END {exit bad}'")

with subtest("tailnet push and scrape, no backend read access"):
    sender.succeed("systemd-cat -t telemetry-test -p err echo telemetry-runtime-marker")
    query = shlex.quote('{host="sender"} |= "telemetry-runtime-marker"')
    collector.wait_until_succeeds(
        "curl -fsSG http://127.0.0.1:3101/loki/api/v1/query_range --data-urlencode query="
        + query + " | jq -e '.data.result | length > 0'"
    )
    sender.succeed("test $(curl -s -o /dev/null -w '%{http_code}' http://collector:3100/loki/api/v1/labels) = 404")
    collector.wait_until_succeeds("curl -fsS http://sender:9100/metrics | grep node_systemd_unit_state >/dev/null")
    collector.wait_until_succeeds("curl -fsSG http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=up{job=\"node\"}' | jq -e '.data.result[0].value[1] == \"1\"'")
    for port in [3101, 9090, 3031, 13100, 19100, 12345]:
        sender.fail(f"curl --connect-timeout 2 --max-time 3 -sS http://collector:{port}/")

with subtest("push gateway forwards Loki acknowledgments and rejects other requests"):
    payload = shlex.quote(json.dumps({"streams": [{
        "stream": {"job": "gateway-fixture"},
        "values": [[sender.succeed("date +%s%N").strip(), "gateway-fixture"]],
    }]}))
    for hostname in ["collector", "127.0.0.1", "arbitrary.example.test"]:
        response = sender.succeed(
            "curl -sS -w '\\n%{http_code}' -H " + shlex.quote("Host: " + hostname)
            + " -H 'Content-Type: application/json' -d " + payload
            + " http://collector:3100/loki/api/v1/push"
        ).strip()
        assert response == "204", response
    sender.succeed("test $(curl -s -o /dev/null -w '%{http_code}' http://collector:3100/loki/api/v1/push) = 404")
    collector.succeed("systemctl stop loki")
    sender.succeed("test $(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{\"streams\":[]}' http://collector:3100/loki/api/v1/push) = 502")
    collector.succeed("systemctl start loki")
    collector.wait_until_succeeds("curl -fsS http://127.0.0.1:3101/ready")


with subtest("LAN denied even with firewall disabled"):
    collector.succeed("systemctl stop firewall")
    # collector's VLAN-2 address, not its trusted VLAN-1 address.
    lan_ip = json.loads(collector.succeed("ip -j -4 addr show eth2"))[0]["addr_info"][0]["local"]
    for port in [3030, 3100, 9100]:
        outsider.fail(f"curl --connect-timeout 2 --max-time 3 -sS http://{lan_ip}:{port}/")
    collector.succeed("systemctl start firewall")

with subtest("authenticated Grafana with provisioned rules and muted notifications"):
    sender.wait_until_succeeds("test $(curl -s -o /dev/null -w '%{http_code}' http://collector:3030/api/search) = 401", timeout=180)
    password = collector.succeed("cat /var/lib/grafana/initial-admin-password").strip()
    auth = shlex.quote("admin:" + password)
    api = "curl -fsS -u " + auth + " http://127.0.0.1:3031"
    collector.succeed(api + "/api/search | jq -e 'any(.[]; .uid == \"telemetry-fleet\")'")
    collector.succeed(api + "/api/v1/provisioning/alert-rules | jq -e 'length == 5'")
    collector.succeed(api + "/api/v1/provisioning/policies | jq -e '.routes[0].mute_time_intervals == [\"inbox-only\"]'")
    collector.succeed("test $(stat -c %a /var/lib/grafana/initial-admin-password) = 600")
    sender.fail("curl -fsS -u admin:admin http://collector:3030/api/search")

with subtest("activation with an existing interface starts listeners"):
    collector.succeed("systemctl stop telemetry-logs.socket")
    collector.succeed("systemctl restart telemetry-listeners.service")
    sender.wait_until_succeeds("curl -fsS http://collector:3100/ready")

with subtest("interface removal and recovery"):
    collector.succeed("ip link set eth1 down")
    collector.succeed("ip link set eth1 name gone0")
    collector.wait_until_fails("systemctl is-active telemetry-logs.socket")
    sender.succeed("systemd-cat -t telemetry-test echo telemetry-interface-recovery")
    collector.succeed("ip link set gone0 name eth1; ip link set eth1 up")
    sender.wait_until_succeeds("curl -fsS http://collector:3100/ready")
    query = shlex.quote('{host="sender"} |= "telemetry-interface-recovery"')
    collector.wait_until_succeeds("curl -fsSG http://127.0.0.1:3101/loki/api/v1/query_range --data-urlencode query=" + query + " | jq -e '.data.result | length > 0'")

with subtest("late interface does not block boot and survives recreation"):
    outsider.wait_for_unit("multi-user.target")
    outsider.fail("systemctl is-active telemetry-metrics.socket")
    outsider.succeed("ip link add late0 type dummy; ip link set late0 up")
    outsider.wait_until_succeeds("systemctl is-active telemetry-metrics.socket", timeout=30)
    outsider.succeed("ip link del late0")
    outsider.wait_until_fails("systemctl is-active telemetry-metrics.socket")
    outsider.succeed("ip link add late0 type dummy; ip link set late0 up")
    outsider.wait_until_succeeds("systemctl is-active telemetry-metrics.socket", timeout=30)

with subtest("alerts evaluate and exclusions preserve searchable logs"):
    sender.succeed("systemd-run --unit telemetry-fixture --wait /bin/sh -c 'echo \"<2>telemetry-fixture-critical\"; for i in a b c d e f g h i j k l m n o; do echo telemetry-fixture-spam-$i; done'")
    sender.succeed("systemd-run --unit telemetry-ignored --wait /bin/sh -c 'for i in a b c d e f g h i j k l m n o; do echo \"<2>telemetry-known-noise-$i\"; done'")
    ignored_query = shlex.quote('{host="sender",unit="telemetry-ignored.service"} |= "telemetry-known-noise"')
    collector.wait_until_succeeds("curl -fsSG http://127.0.0.1:3101/loki/api/v1/query_range --data-urlencode query=" + ignored_query + " | jq -e '.data.result | length > 0'")
    rules = api + "/api/prometheus/grafana/api/v1/rules"
    # A real firing instance verifies the data-source query and expression model,
    # not merely that Grafana accepted a provisioning file.
    for title in ["Journal errors", "Critical journal messages", "Journal spam"]:
        condition = 'any(.data.groups[].rules[].alerts[]?; .labels.unit == "telemetry-fixture.service" and .labels.alertname == ' + json.dumps(title) + ' and (.state == "Alerting" or .state == "firing"))'
        collector.wait_until_succeeds(rules + " | jq -e " + shlex.quote(condition), timeout=180)
    collector.succeed(rules + " | jq -e 'all(.data.groups[].rules[].alerts[]?; .labels.unit != \"telemetry-ignored.service\")'")

    history_query = shlex.quote('{from="state-history"}')
    collector.wait_until_succeeds("curl -fsSG http://127.0.0.1:3101/loki/api/v1/query_range --data-urlencode query=" + history_query + " | jq -e '.data.result | length > 0'", timeout=90)


def emit_recovery_batch(prefix: str) -> None:
    sender.succeed(
        "for i in $(seq 1 12); do echo " + shlex.quote(prefix) + "-$i; done"
        + " | systemd-cat -t telemetry-recovery"
    )
    sender.succeed("journalctl --sync")


def assert_recovery_batch(prefix: str) -> None:
    query = shlex.quote('{host="sender"} |= ' + json.dumps(prefix + "-"))
    # Exact unique fixtures detect both missing entries and visible replay
    # duplicates. Loki can deduplicate identical timestamp/label/line triples.
    collector.wait_until_succeeds(
        "curl -fsSG http://127.0.0.1:3101/loki/api/v1/query_range"
        + " --data-urlencode limit=1000 --data-urlencode query=" + query
        + " | jq -e '[.data.result[].values[][1]] | (length == 12) and (unique | length == 12)'",
        timeout=120,
    )


with subtest("journal cursor resumes after collection is stopped"):
    sender.succeed("systemctl stop alloy")
    emit_recovery_batch("telemetry-cursor-recovery")
    sender.succeed("systemctl start alloy")
    assert_recovery_batch("telemetry-cursor-recovery")
