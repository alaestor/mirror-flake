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
        alloyHttpPort = 12346;
      };
      services.prometheus.port = 9091;
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
  # Assert user-visible semantics and exposure, not dashboard appearance.
  checks = {
    dashboardIdentity = dashboard.uid == "telemetry-fleet" && !dashboard.editable;
    dashboardTimeRange = dashboard.time.from == "now-7d";
    homeDashboard = (builtins.fromJSON (
      builtins.readFile server.services.grafana.settings.dashboards.default_home_dashboard_path
    )).uid == dashboard.uid;
    uptime = (panel 16).fieldConfig.defaults.min == 0
      && (panel 16).fieldConfig.defaults.max == 100
      && (panel 16).fieldConfig.defaults.unit == "percent"
      && (builtins.head (panel 16).targets).instant
      && !(builtins.head (panel 16).targets).range
      && (builtins.head (panel 16).targets).expr
        == "100 * avg_over_time(up{job=\"node\",host=~\"\${host:regex}\"}[$__range])"
      && (builtins.head (panel 16).targets).legendFormat == "{{host}}";
    hostSelection = (variable "host").multi && (variable "host").includeAll
      && (panel 11).repeat == "host";
    currentMetrics = builtins.all (id:
      (panel id).fieldConfig.defaults.noValue == "Unknown"
      && (builtins.head (panel id).targets).instant
      && lib.hasInfix "\${host:regex}" (builtins.head (panel id).targets).expr
    ) [ 17 18 19 ];
    cpuQuery = lib.hasInfix "rate(node_cpu_seconds_total" (builtins.head (panel 17).targets).expr;
    memoryQuery = lib.hasInfix "node_memory_MemAvailable_bytes" (builtins.head (panel 18).targets).expr;
    temperatureQuery = lib.hasInfix "max by (host) (node_hwmon_temp_celsius" (builtins.head (panel 19).targets).expr;
    defaultSeverity = (variable "journal_severity").current.value == "[0-4]";
    hostLegend = (builtins.head (panel 4).targets).legendFormat == "{{host}}";
    eventOverviews = !(builtins.any (p: p.type == "logs") dashboard.panels)
      && builtins.all (p:
        p.type == "fleet-event-families-panel"
        && (builtins.head p.targets).queryType == "instant"
        && lib.hasInfix "count_over_time(" (builtins.head p.targets).expr
        && lib.hasInfix "[$__range]" (builtins.head p.targets).expr
        && lib.hasInfix "\${journal_search:doublequote}" (builtins.head p.targets).expr
        && lib.hasInfix "\${journal_noise:doublequote}" (builtins.head p.targets).expr
        && !lib.hasInfix ":json}" (builtins.head p.targets).expr
        && (builtins.head p.transformations).id == "labelsToFields"
        && (builtins.elemAt p.transformations 1).options.renameByName."Value #A" == "Count"
        && builtins.any (override:
          override.matcher.options == "Event family"
          && builtins.any (property: property.id == "links") override.properties
        ) p.fieldConfig.overrides
      ) eventOverviews;
    sharedOverviewQuery = (builtins.head (panel 1).targets).expr == (builtins.head (panel 15).targets).expr;
    pluginRegistration = server.services.grafana.settings.plugins.allow_loading_unsigned_plugins
      == "fleet-event-families-panel";
    defaultNoiseFilter = (variable "journal_noise").current.value == "a^";
    timeRangeControl = !(dashboard.timepicker.hidden or false);
    noLegacyCollector = !client.services.vector.enable;
    disabledWorkloads = !disabled.telemetry.enable
      && !disabled.services.alloy.enable && !disabled.services.loki.enable
      && !disabled.services.prometheus.enable && !disabled.services.grafana.enable;
    disabledIngress = disabled.networking.firewall.allowedTCPPorts == [ ];
    clientWorkloads = client.services.alloy.enable
      && client.services.prometheus.exporters.node.enable && !client.services.loki.enable;
    clientPushUrl = client.telemetry.pushUrl == "http://${inputs.self.fleet.telemetry.server}.${
      inputs.self.fleet.tailnets.${inputs.self.fleet.telemetry.tailnet}.dnsSuffix
    }:3100/loki/api/v1/push";
    serverPushUrl = server.telemetry.enable && server.telemetry.pushUrl == "http://127.0.0.1:3101/loki/api/v1/push";
    serverIngress = server.networking.firewall.allowedTCPPorts == [ ];
    grafanaLoopback = server.services.grafana.settings.server.http_addr == "127.0.0.1";
    grafanaAuthentication = !server.services.grafana.settings."auth.anonymous".enabled
      && !server.services.grafana.settings.users.allow_sign_up;
    customPushUrl = custom.telemetry.pushUrl == "http://override.test/push";
    customAlloyHttp = lib.elem "--server.http.listen-addr=127.0.0.1:12346"
      custom.services.alloy.extraFlags;
    customPrometheusClients = lib.any (source:
      source.type == "prometheus" && source.url == "http://127.0.0.1:9091"
    ) custom.services.grafana.provision.datasources.settings.datasources
      && lib.any (job: job.job_name == "collector"
        && lib.any (target: target.targets == [ "127.0.0.1:9091" ]) job.static_configs
      ) custom.services.prometheus.scrapeConfigs;
    customInterface = custom.systemd.sockets.telemetry-grafana.socketConfig.BindToDevice == "testvpn";
    customIngress = custom.networking.firewall.interfaces.testvpn.allowedTCPPorts == [ 3039 3100 9100 ];
  };
  failures = lib.attrNames (lib.filterAttrs (_: passed: !passed) checks);
in
assert lib.assertMsg (failures == [ ])
  "telemetry contracts failed: ${lib.concatStringsSep ", " failures}";
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
