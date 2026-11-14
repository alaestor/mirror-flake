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
  checks = [
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
    touch "$out"
  ''
