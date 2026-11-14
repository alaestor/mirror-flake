{
  lib,
  ignoredPatterns,
  spamThreshold,
}:
let
  exclude = lib.concatMapStrings (pattern: " !~ ${builtins.toJSON pattern}") ignoredPatterns;
  journal = ''{job="journal"}'';
  errors = ''{job="journal",priority=~"[0-3]"}'';
  count = selector: "sum by (host, unit) (count_over_time(${selector}${exclude}[5m]))";
  rule =
    {
      uid,
      title,
      expr,
      threshold,
      datasource,
      severity,
      pending ? "0s",
    }:
    {
      inherit uid title;
      condition = "B";
      for = pending;
      noDataState = "OK";
      execErrState = "Error";
      labels = {
        inherit severity;
        category = "telemetry";
      };
      annotations.summary = "${title}: {{ $labels.host }} {{ $labels.unit }}";
      data = [
        {
          refId = "A";
          datasourceUid = "telemetry-${datasource}";
          relativeTimeRange = {
            from = 600;
            to = 0;
          };
          model = {
            inherit expr;
            refId = "A";
            instant = true;
            range = false;
            queryType = "instant";
            intervalMs = 1000;
            maxDataPoints = 43200;
          };
        }
        {
          refId = "B";
          datasourceUid = "__expr__";
          relativeTimeRange = {
            from = 0;
            to = 0;
          };
          model = {
            refId = "B";
            type = "threshold";
            expression = "A";
            conditions = [
              {
                type = "query";
                evaluator = {
                  type = "gt";
                  params = [ threshold ];
                };
                operator.type = "and";
                reducer = {
                  type = "last";
                  params = [ ];
                };
                query.params = [ "B" ];
              }
            ];
          };
        }
      ];
    };
in
{
  apiVersion = 1;
  groups = [
    {
      orgId = 1;
      name = "fleet";
      folder = "Telemetry";
      interval = "1m";
      rules = map rule [
        {
          uid = "telemetry-priority";
          title = "Journal errors";
          expr = count errors;
          threshold = 0;
          datasource = "loki";
          severity = "warning";
        }
        {
          uid = "telemetry-critical";
          title = "Critical journal messages";
          expr = count ''{job="journal",priority=~"[0-2]"}'';
          threshold = 0;
          datasource = "loki";
          severity = "critical";
        }
        {
          uid = "telemetry-spam";
          title = "Journal spam";
          expr = count journal;
          threshold = spamThreshold;
          datasource = "loki";
          severity = "warning";
        }
        {
          uid = "telemetry-failed-units";
          title = "Failed systemd units";
          expr = ''sum by (host, name) (node_systemd_unit_state{state="failed"})'';
          threshold = 0;
          datasource = "prometheus";
          severity = "warning";
          pending = "2m";
        }
        {
          uid = "telemetry-disk";
          title = "Local disk below 10 percent free";
          expr = ''100 * (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|nfs.*|cifs|fuse.*",mountpoint!~"/nix/store.*"} / node_filesystem_size_bytes)'';
          threshold = 90;
          datasource = "prometheus";
          severity = "warning";
          pending = "10m";
        }
      ];
    }
  ];
}
