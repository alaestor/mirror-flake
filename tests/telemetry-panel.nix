{ inputs, pkgs, ... }:
let
  lib = inputs.unstable-nixpkgs.lib;
  server =
    (lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        inputs.self.modules.nixos.telemetry-server
        { telemetry-server.enable = true; }
      ];
    }).config;
in
pkgs.runCommand "telemetry-panel-browser-validation"
  {
    nativeBuildInputs = [ pkgs.nodejs ];
    TELEMETRY_GRAFANA_PACKAGE = server.services.grafana.package;
    TELEMETRY_PLUGIN_PATHS = builtins.toJSON (map toString server.services.grafana.declarativePlugins);
    TELEMETRY_DASHBOARD = inputs.self.data.path "features/telemetry/dashboards/fleet.json";
    TELEMETRY_CHROMIUM = "${pkgs.chromium}/bin/chromium";
    FONTCONFIG_FILE = pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; };
  }
  ''
    timeout 300s node ${inputs.self}/tests/telemetry/event-panel-browser.cjs
    touch "$out"
  ''
