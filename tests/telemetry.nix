{
  inputs,
  pkgs,
  system,
}:
let
  lib = inputs.unstable-nixpkgs.lib;
  evaluate = modules: (lib.nixosSystem { inherit system modules; }).config;
  disabled = evaluate [ inputs.self.modules.nixos.telemetry-server ];
  client = evaluate [
    inputs.self.modules.nixos.telemetry
    { telemetry.enable = true; }
  ];
  server = evaluate [
    inputs.self.modules.nixos.telemetry-server
    { telemetry-server.enable = true; }
  ];
  custom = evaluate [
    inputs.self.modules.nixos.telemetry-server
    {
      telemetry-server = {
        enable = true;
        grafanaPort = 3039;
        clients = [ "example.test" ];
      };
      telemetry = {
        interface = "testvpn";
        pushUrl = "http://override.test/push";
      };
    }
  ];
  dashboard = inputs.self.data.readJSON "features/telemetry/dashboards/fleet.json";
  panel =
    id: lib.findFirst (p: p.id == id) (throw "Missing telemetry panel ${toString id}") dashboard.panels;
  variable =
    name:
    lib.findFirst (
      v: v.name == name
    ) (throw "Missing telemetry variable ${name}") dashboard.templating.list;
  eventOverviews = map panel [
    1
    15
  ];
  checks = [
    (dashboard.uid == "telemetry-fleet" && !dashboard.editable && dashboard.time.from == "now-7d")
    (
      (builtins.fromJSON (
        builtins.readFile server.services.grafana.settings.dashboards.default_home_dashboard_path
      )).uid == dashboard.uid
    )
    (
      (builtins.head dashboard.panels).id == 16
      && (panel 16).gridPos.y == 0
      && (panel 16).gridPos.w == 24
      && (panel 16).fieldConfig.defaults.min == 0
      && (panel 16).fieldConfig.defaults.max == 100
      && (panel 16).fieldConfig.defaults.unit == "percent"
      && (panel 16).type == "bargauge"
      && (panel 16).options.displayMode == "basic"
      && (panel 16).options.orientation == "horizontal"
      &&
        (panel 16).fieldConfig.defaults.color == {
          mode = "fixed";
          fixedColor = "green";
        }
      && (builtins.head (panel 16).targets).instant
      && !(builtins.head (panel 16).targets).range
      &&
        (builtins.head (panel 16).targets).expr
        == "100 * avg_over_time(up{job=\"node\",host=~\"\${host:regex}\"}[$__range])"
      && (builtins.head (panel 16).targets).legendFormat == "{{host}}"
    )
    ((variable "host").multi && (variable "host").includeAll && (panel 11).repeat == "host")
    (builtins.all
      (
        id:
        (panel id).type == "gauge"
        && (panel id).gridPos.y > (panel 11).gridPos.y
        && (panel id).gridPos.y < (panel 13).gridPos.y
        && (panel id).fieldConfig.defaults.noValue == "Unknown"
        && (builtins.head (panel id).targets).instant
        && lib.hasInfix "\${host:regex}" (builtins.head (panel id).targets).expr
      )
      [
        17
        18
        19
      ]
    )
    (lib.hasInfix "rate(node_cpu_seconds_total" (builtins.head (panel 17).targets).expr)
    (lib.hasInfix "node_memory_MemAvailable_bytes" (builtins.head (panel 18).targets).expr)
    (lib.hasInfix "max by (host) (node_hwmon_temp_celsius" (builtins.head (panel 19).targets).expr)
    ((variable "journal_severity").current.value == "[0-4]")
    ((panel 1).gridPos.y < (panel 11).gridPos.y)
    ((panel 3).gridPos.x + (panel 3).gridPos.w == (panel 6).gridPos.x)
    ((builtins.head (panel 4).targets).legendFormat == "{{host}}")
    (
      !(builtins.any (p: p.type == "logs") dashboard.panels)
      && builtins.all (
        p:
        p.type == "fleet-event-families-panel"
        && (builtins.head p.targets).queryType == "instant"
        && lib.hasInfix "count_over_time(" (builtins.head p.targets).expr
        && lib.hasInfix "[$__range]" (builtins.head p.targets).expr
        && lib.hasInfix "\${journal_search:doublequote}" (builtins.head p.targets).expr
        && lib.hasInfix "\${journal_noise:doublequote}" (builtins.head p.targets).expr
        && !lib.hasInfix ":json}" (builtins.head p.targets).expr
        && (builtins.head p.transformations).id == "labelsToFields"
        && (builtins.elemAt p.transformations 1).options.renameByName."Value #A" == "Count"
        && builtins.any (
          override:
          override.matcher.options == "Event family"
          && builtins.any (property: property.id == "links") override.properties
        ) p.fieldConfig.overrides
      ) eventOverviews
    )
    ((builtins.head (panel 1).targets).expr == (builtins.head (panel 15).targets).expr)
    (
      server.services.grafana.settings.plugins.allow_loading_unsigned_plugins
      == "fleet-event-families-panel"
    )
    ((variable "journal_noise").current.value == "a^")
    (dashboard.links == [ ] && !(dashboard.timepicker.hidden or false))
    (client.services.alloy.package.drvPath != pkgs.grafana-alloy.drvPath)
    (!client.services.vector.enable)
    (lib.hasInfix "max_backoff_retries = 0" (builtins.readFile client.services.alloy.configPath))
    (
      !disabled.telemetry.enable
      && !disabled.services.alloy.enable
      && !disabled.services.loki.enable
      && !disabled.services.prometheus.enable
      && !disabled.services.grafana.enable
    )
    (disabled.networking.firewall.allowedTCPPorts == [ ])
    (
      client.services.alloy.enable
      && client.services.prometheus.exporters.node.enable
      && !client.services.loki.enable
    )
    (
      client.telemetry.pushUrl == "http://${inputs.self.fleet.telemetry.server}.${
        inputs.self.fleet.tailnets.${inputs.self.fleet.telemetry.tailnet}.dnsSuffix
      }:3100/loki/api/v1/push"
    )
    (server.telemetry.enable && server.telemetry.pushUrl == "http://127.0.0.1:3101/loki/api/v1/push")
    (server.networking.firewall.allowedTCPPorts == [ ])
    (server.services.loki.configuration.limits_config.max_query_series == 5000)
    (server.services.loki.configuration.server.grpc_server_max_recv_msg_size == 32 * 1024 * 1024)
    (server.services.loki.configuration.limits_config.split_instant_metric_queries_by_interval == "24h")
    (server.services.grafana.settings.server.http_addr == "127.0.0.1")
    (
      !server.services.grafana.settings."auth.anonymous".enabled
      && !server.services.grafana.settings.users.allow_sign_up
    )
    (custom.telemetry.pushUrl == "http://override.test/push")
    (custom.systemd.sockets.telemetry-grafana.socketConfig.BindToDevice == "testvpn")
    (
      custom.networking.firewall.interfaces.testvpn.allowedTCPPorts == [
        3039
        3100
        9100
      ]
    )
  ];
in
assert lib.assertMsg (builtins.all (
  x: x
) checks) "telemetry isolation/default/override contract failed";
pkgs.runCommand "telemetry-config-validation"
  {
    nativeBuildInputs = [
      server.services.alloy.package
      pkgs.prometheus.cli
      pkgs.nodejs
    ];
    config = server.services.alloy.configPath;
    # Referencing ExecStart also builds nixpkgs' native Loki config validator.
    lokiCommand = server.systemd.services.loki.serviceConfig.ExecStart;
    prometheusConfig = pkgs.writeText "prometheus.json" (
      builtins.toJSON {
        global = server.services.prometheus.globalConfig;
        scrape_configs = server.services.prometheus.scrapeConfigs;
      }
    );
  }
  ''
    alloy validate "$config"
    promtool check config "$prometheusConfig"
    EVENT_PANEL_MODEL=${inputs.self.data.path "features/telemetry/event-panel/model.js"} \
      node --test ${inputs.self}/tests/telemetry/event-panel.test.cjs
    touch "$out"
  ''
