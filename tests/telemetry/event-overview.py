

with subtest("event overview condenses classes over the full range and links to raw occurrences"):
    import urllib.parse

    dashboard = json.loads(collector.succeed(api + "/api/dashboards/uid/telemetry-fleet"))["dashboard"]
    overview = next(panel for panel in dashboard["panels"] if panel["id"] == 1)
    query_template = overview["targets"][0]["expr"]
    now = int(collector.succeed("date +%s%N").strip())

    def event_query(host="event-fixture-.*", unit=".*", priority=".*", search="", noise="a^", window="5m"):
        query = query_template
        for name, value in {
            "${host:regex}": host,
            "${journal_unit:regex}": unit,
            "${journal_severity:raw}": priority,
            "${journal_search:doublequote}": json.dumps(search),
            "${journal_noise:doublequote}": json.dumps(noise),
            "$__range": window,
        }.items():
            query = query.replace(name, value)
        return query

    def metric_query(query):
        return json.loads(collector.succeed(
            "curl -fsSG http://127.0.0.1:3101/loki/api/v1/query --data-urlencode query="
            + shlex.quote(query) + " --data-urlencode time=" + str(now / 10**9 + 1)
        ))["data"]["result"]

    streams = []

    def fixture(messages, host="event-fixture-a", unit="user@1000.service", priority="3", source="dbus-broker", age=0):
        labels = {"job": "journal", "host": host}
        if unit is not None:
            labels["unit"] = unit
        if priority is not None:
            labels["priority"] = priority
        metadata = {"syslog_identifier": source} if source else {}
        offset = sum(len(stream["values"]) for stream in streams)
        streams.append({"stream": labels, "values": [
            [str(now - age + offset + i), message, metadata] for i, message in enumerate(messages)
        ]})

    duplicates = [
        "Ignoring duplicate name 'org.example.Service" + str(i)
        + "' in service file '/nix/store/" + str(i).zfill(32)
        + "-system-path/share/dbus-1/services/org.example.Service" + str(i) + ".service'"
        for i in range(600)
    ]
    fixture(duplicates)
    fixture([duplicates[0]], host="event-fixture-b")
    fixture([duplicates[0]], unit="other.service")
    fixture([duplicates[0]], priority="4")
    fixture([duplicates[0]], source="other-broker")
    fixture([duplicates[0]], source=None)
    # An older occurrence must not inflate the selected five-minute count.
    fixture([duplicates[0]], age=10 * 60 * 10**9)
    fixture(["Failed to activate name 'org.example.Service1' in service file '/run/example.service'"])
    fixture(["Cannot open '/run/first': Permission denied", "Cannot open '/run/second': No such file or directory"])
    fixture(["Processed 12 requests in 2.5 seconds", "Processed 34 requests in 3.7 seconds"])
    fixture(["Operation failed: 'Access denied'", "Operation failed: 'Out of memory'"])
    fixture(["Request 550e8400-e29b-41d4-a716-446655440000 failed", "Request 550e8400-e29b-41d4-a716-446655440001 failed"])
    fixture(['Could not process "quoted" request & retry: \\backslash\nsecond line ☃'])
    fixture(["Unattributed failure"], unit=None, priority=None, source=None)
    progress = [
        "\r  0%|          | 0/8 [00:00<?, ?it/s]"
        + "".join(
            "\r" + str(round(i / 8 * 100)).rjust(3) + "%|" + "█" * i
            + " " * (10 - i) + "| " + str(i) + "/8 [00:01<00:01, 5.59it/s]"
            for i in range(1, 9)
        )
        + "\r100%|██████████| 8/8 [00:01<00:00, 5.59it/s]\n",
        "\r 12%|█▎        | 12/100 [00:02<00:18, 4.75it/s]",
        " 50%|#####5     | 50/100 [01:02<01:02, 1.25s/it]\n",
        "100%|████████████████████| 200/200 [01:02:03<00:00, 3.22it/s]",
    ]
    fixture(progress, source="progress-worker")
    # A bar next to diagnostics is not a progress-only record.
    mixed_progress = [
        "ERROR: model failed\n" + progress[1],
        progress[1] + "\nERROR: device lost",
        "Loading model: " + progress[1],
    ]
    fixture(mixed_progress, source="progress-worker")
    # Crash handlers get a fresh system unit per crash. Those hidden units
    # must not split otherwise identical families or narrow their Explore links.
    crash_source = "systemd-coredump"
    crash_family = "Process <n> (chromium) of user <n> terminated abnormally without generating a coredump."
    socket_family = 'The socket path doesn\'t exist @ "<path>"'
    crash_message = "Process 2866847 (chromium) of user 30011 terminated abnormally without generating a coredump."
    for index, pid in enumerate([2866847, 2861178, 2868910]):
        instance = "292-49181-" + str(pid) + "_15416743-0.service"
        fixture([crash_message.replace("2866847", str(pid))],
                unit="systemd-coredump@" + instance, priority="2", source=crash_source)
        fixture(['The socket path doesn\'t exist @ "/run/user/' + str(30011 + index) + '/drkonqi-coredump-launcher"'],
                unit="drkonqi-coredump-processor@" + instance, priority="4", source="drkonqi-coredump-processor")
    # Instance identity still matters for ordinary templates.
    for unit in ["worker@alpha.service", "worker@beta.service"]:
        fixture([crash_message], unit=unit, priority="2", source=crash_source)
    fixture([crash_message], unit="systemd-coredump@other.service", priority="3", source=crash_source)
    fixture([crash_message], host="event-fixture-b", unit="systemd-coredump@other.service", priority="2", source=crash_source)
    fixture([crash_message.replace("chromium", "firefox")], unit="systemd-coredump@other.service", priority="2", source=crash_source)
    # Missing identifiers fall back to the normalized template, not an instance.
    for unit in ["systemd-coredump@first.service", "systemd-coredump@second.service"]:
        fixture([crash_message], unit=unit, priority="2", source=None)
    # Keep each shell argument below execve's per-argument size limit.
    for stream in streams:
        for offset in range(0, len(stream["values"]), 100):
            payload = json.dumps({"streams": [{**stream, "values": stream["values"][offset:offset + 100]}]})
            collector.succeed(
                "curl -fsS -H 'Content-Type: application/json' -d " + shlex.quote(payload)
                + " http://127.0.0.1:3101/loki/api/v1/push"
            )
    query = event_query()
    collector.wait_until_succeeds(
        "curl -fsSG http://127.0.0.1:3101/loki/api/v1/query --data-urlencode query="
        + shlex.quote(query) + " --data-urlencode time=" + str(now / 10**9 + 1)
        + " | jq -e '[.data.result[].value[1] | tonumber] | add == 636'",
        timeout=60,
    )
    rows = metric_query(query)
    duplicate_family = "Ignoring duplicate name <name> in service file '<path>'"
    grouped = [row for row in rows if row["metric"]["event"] == duplicate_family]
    assert sorted(int(row["value"][1]) for row in grouped) == [1, 1, 1, 1, 1, 600], grouped
    events = {row["metric"]["event"] for row in rows}
    assert "Cannot open '<path>': Permission denied" in events, events
    assert "Cannot open '<path>': No such file or directory" in events, events
    assert "Operation failed: 'Access denied'" in events, events
    assert "Operation failed: 'Out of memory'" in events, events
    assert any(event.startswith("Failed to activate name ") for event in events), events
    assert any(row["metric"]["event"] == "Processed <n> requests in <n> seconds" and row["value"][1] == "2" for row in rows), rows
    assert any(row["metric"]["event"] == "Request <id> failed" and row["value"][1] == "2" for row in rows), rows
    assert any(row["metric"].get("source") == "unknown" for row in rows), rows
    progress_rows = [row for row in rows if row["metric"]["source"] == "progress-worker"]
    assert len(progress_rows) == 4, progress_rows
    assert next(row["value"][1] for row in progress_rows if row["metric"]["event"] == "Iteration progress output") == "4", progress_rows
    assert any("ERROR: model failed" in row["metric"]["event"] for row in progress_rows), progress_rows
    assert any("ERROR: device lost" in row["metric"]["event"] for row in progress_rows), progress_rows
    assert any("Loading model:" in row["metric"]["event"] for row in progress_rows), progress_rows

    crash_rows = [row for row in rows if row["metric"]["event"] == crash_family
                  and row["metric"]["unit"] == "systemd-coredump@.service"]
    assert sorted(int(row["value"][1]) for row in crash_rows) == [1, 1, 2, 3], crash_rows
    assert any(row["metric"]["source"] == "systemd-coredump@.service" and row["value"][1] == "2"
               for row in crash_rows), crash_rows
    socket_rows = [row for row in rows if row["metric"]["event"] == socket_family]
    assert len(socket_rows) == 1 and socket_rows[0]["value"][1] == "3", socket_rows
    assert socket_rows[0]["metric"]["unit"] == "drkonqi-coredump-processor@.service", socket_rows
    worker_rows = [row for row in rows if row["metric"].get("unit", "").startswith("worker@")]
    assert len(worker_rows) == 2 and all(row["value"][1] == "1" for row in worker_rows), worker_rows

    # Resolve the actual table data link, including JSON/URL escaping and range.
    link = next(
        prop["value"][0]["url"]
        for override in overview["fieldConfig"]["overrides"]
        for prop in override["properties"] if prop["id"] == "links"
    )
    for row in rows:
        url = link.replace("${__data.fields.details:raw}", row["metric"]["details"])
        url = url.replace("${__from}", str(now // 10**6 - 300000)).replace("${__to}", str(now // 10**6 + 1000))
        params = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)
        pane = json.loads(params["panes"][0])["events"]
        raw_query = pane["queries"][0]["expr"]
        matches = metric_query("sum(count_over_time(" + raw_query + " [5m]))")
        assert matches[0]["value"][1] == row["value"][1], (row, matches)
        assert pane["range"]["from"] == str(now // 10**6 - 300000), pane

    # Dashboard filters operate on original messages, not placeholder text.
    filtered = metric_query(event_query(host="event-fixture-a", unit="other[.]service", priority="3", search="Service0"))
    assert len(filtered) == 1 and filtered[0]["value"][1] == "1", filtered
    assert not metric_query(event_query(search="does not exist"))
    hidden = metric_query(event_query(noise="^Ignoring duplicate name "))
    assert all(row["metric"]["event"] != duplicate_family for row in hidden), hidden
    raw = json.loads(collector.succeed(
        "curl -fsSG http://127.0.0.1:3101/loki/api/v1/query_range --data-urlencode query="
        + shlex.quote('{job="journal",host="event-fixture-a",unit="user@1000.service",priority="3"} |= "Ignoring duplicate name"')
        + " --data-urlencode limit=1000"
    ))["data"]["result"]
    assert any(value[1] == duplicates[599] for stream in raw for value in stream["values"]), raw
    raw_progress = json.loads(collector.succeed(
        "curl -fsSG http://127.0.0.1:3101/loki/api/v1/query_range --data-urlencode query="
        + shlex.quote('{job="journal",host="event-fixture-a"} | syslog_identifier="progress-worker"')
    ))["data"]["result"]
    assert any(value[1] == progress[0] for stream in raw_progress for value in stream["values"]), raw_progress

with subtest("seven-day overview returns more than 500 distinct normalized families without truncation"):
    import itertools
    import string

    # Alphabetic suffixes survive normalization. Numeric fixture IDs would
    # collapse to <n> and miss the production cardinality failure.
    messages = ["Distinct failure " + "".join(letters)
                for letters in itertools.islice(itertools.product(string.ascii_lowercase, repeat=3), 1500)]
    streams = []
    fixture(messages, host="event-cardinality", age=10 * 60 * 10**9)
    fixture(messages, host="event-cardinality")
    for stream in streams:
        for offset in range(0, len(stream["values"]), 100):
            payload = json.dumps({"streams": [{**stream, "values": stream["values"][offset:offset + 100]}]})
            collector.succeed(
                "curl -fsS -H 'Content-Type: application/json' -d " + shlex.quote(payload)
                + " http://127.0.0.1:3101/loki/api/v1/push"
            )
    rows = metric_query(event_query(host="event-cardinality", window="7d"))
    assert len(rows) == 1500, len(rows)
    assert {row["metric"]["event"] for row in rows} == set(messages)
    assert all(row["value"][1] == "2" for row in rows), rows
    # details must be a function of identity, not of the raw record or time.
    for row in [rows[0], rows[-1]]:
        raw_query = json.loads(urllib.parse.unquote_plus(row["metric"]["details"]))
        matches = metric_query("sum(count_over_time(" + raw_query + " [7d]))")
        assert matches[0]["value"][1] == "2", matches
    recent = metric_query(event_query(host="event-cardinality", window="5m"))
    assert len(recent) == 1500 and all(row["value"][1] == "1" for row in recent)
