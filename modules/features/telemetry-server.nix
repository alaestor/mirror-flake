/**
  Central telemetry storage, authenticated Grafana, and inbox-only alerts.

  Extends telemetry so the collector also ships its own journal. Loki and
  Prometheus remain on loopback; a push-only HTTP gateway and Grafana are
  exposed through interface-bound sockets, without public domain routes.
  Local state is disposable observability data, not a backup of source hosts.
  See docs/telemetry.md before changing retention, auth, or notification policy.
*/
{
  config,
  inputs,
  self,
  ...
}:
let
  fleet = config.flake.fleet;
  suffix = fleet.tailnets.${fleet.telemetry.tailnet}.dnsSuffix;
in
{
  flake.modules.nixos.telemetry-server =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.telemetry-server;
      ingressFile = pkgs.writeText "telemetry-ingress.Caddyfile" (
        lib.replaceStrings
          [ "@ingressBackendPort@" "@lokiPort@" ]
          [ (toString cfg.ingressBackendPort) (toString cfg.lokiPort) ]
          (self.data.read "features/telemetry/ingress.Caddyfile")
      );
      ingress = pkgs.runCommand "telemetry-ingress.json" { nativeBuildInputs = [ pkgs.caddy ]; } ''
        export XDG_DATA_HOME="$TMPDIR/caddy-data"
        export XDG_CONFIG_HOME="$TMPDIR/caddy-config"
        caddy adapt --config ${ingressFile} --adapter caddyfile --validate > "$out"
      '';
      passwordFile = "${config.services.grafana.dataDir}/initial-admin-password";
      secretFile = "${config.services.grafana.dataDir}/secret-key";
      initSecrets = pkgs.writeShellScript "grafana-init-secrets" ''
        set -eu
        umask 077
        for file in ${
          lib.escapeShellArgs [
            passwordFile
            secretFile
          ]
        }; do
          if [ ! -s "$file" ]; then
            ${pkgs.openssl}/bin/openssl rand -hex 32 > "$file"
          fi
        done
      '';
      alerts = import (self.data.path "features/telemetry/alerts.nix") {
        inherit lib;
        inherit (cfg.alerts) ignoredPatterns spamThreshold;
      };
    in
    {
      imports = [ inputs.self.modules.nixos.telemetry ];
      options.telemetry-server = {
        enable = lib.mkEnableOption "central fleet telemetry";
        clients = lib.mkOption {
          type = lib.types.listOf lib.types.nonEmptyStr;
          default = map (host: "${host}.${suffix}") fleet.telemetry.clients;
          description = "Tailnet DNS names to scrape; independent of other host evaluations.";
        };
        grafanaPort = lib.mkOption {
          type = lib.types.port;
          default = 3030;
          description = "Tailnet Grafana port.";
        };
        grafanaBackendPort = lib.mkOption {
          type = lib.types.port;
          default = 3031;
          description = "Loopback Grafana port.";
        };
        ingressPort = lib.mkOption {
          type = lib.types.port;
          default = 3100;
          description = "Tailnet log-push port.";
        };
        ingressBackendPort = lib.mkOption {
          type = lib.types.port;
          default = 13100;
          description = "Loopback push-only proxy port.";
        };
        lokiPort = lib.mkOption {
          type = lib.types.port;
          default = 3101;
          description = "Loopback Loki API port.";
        };
        publicUrl = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "http://${fleet.telemetry.server}.${suffix}:${toString cfg.grafanaPort}/";
          description = "Browser-facing Grafana URL, reached through the encrypted tailnet.";
        };
        logRetention = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "336h";
          description = "Loki retention duration, minimum 24h.";
        };
        metricsRetention = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "30d";
          description = "Prometheus time retention.";
        };
        metricsSize = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "5GB";
          description = "Prometheus size retention, in addition to time retention.";
        };
        alerts = {
          ignoredPatterns = lib.mkOption {
            type = lib.types.listOf lib.types.nonEmptyStr;
            default = [ ];
            description = "RE2 line patterns excluded from all log alert rules, but never from stored logs. Match narrowly.";
          };
          spamThreshold = lib.mkOption {
            type = lib.types.ints.positive;
            default = 1000;
            description = "Messages per host and unit in five minutes that trigger the spam alert.";
          };
        };
      };
      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = config.telemetry.enable;
            message = "telemetry-server requires telemetry.enable for local journal collection.";
          }
        ];
        telemetry = {
          enable = lib.mkDefault true;
          pushUrl = lib.mkDefault "http://127.0.0.1:${toString cfg.lokiPort}/loki/api/v1/push";
          listeners = {
            logs = {
              port = cfg.ingressPort;
              backendPort = cfg.ingressBackendPort;
            };
            grafana = {
              port = cfg.grafanaPort;
              backendPort = cfg.grafanaBackendPort;
            };
          };
        };
        # Return Loki's response directly, instead of acknowledging into a
        # second shipper/WAL. This keeps the client's acknowledgment end to end.
        systemd.services.telemetry-ingress = {
          description = "Push-only telemetry ingress";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          environment = {
            XDG_DATA_HOME = "/var/lib/telemetry-ingress";
            XDG_CONFIG_HOME = "/var/lib/telemetry-ingress";
          };
          serviceConfig = {
            ExecStart = "${pkgs.caddy}/bin/caddy run --config ${ingress}";
            Restart = "always";
            RestartSec = 5;
            DynamicUser = true;
            StateDirectory = "telemetry-ingress";
            NoNewPrivileges = true;
            CapabilityBoundingSet = "";
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateDevices = true;
          };
        };
        services.loki = {
          enable = true;
          configuration = {
            auth_enabled = false;
            analytics.reporting_enabled = false;
            server = {
              http_listen_address = "127.0.0.1";
              http_listen_port = cfg.lokiPort;
              grpc_listen_address = "127.0.0.1";
            };
            common = {
              path_prefix = config.services.loki.dataDir;
              replication_factor = 1;
              instance_addr = "127.0.0.1";
              ring.kvstore.store = "inmemory";
              storage.filesystem = {
                chunks_directory = "${config.services.loki.dataDir}/chunks";
                rules_directory = "${config.services.loki.dataDir}/rules";
              };
            };
            schema_config.configs = [
              {
                from = "2024-01-01";
                store = "tsdb";
                object_store = "filesystem";
                schema = "v13";
                index = {
                  prefix = "index_";
                  period = "24h";
                };
              }
            ];
            compactor = {
              working_directory = "${config.services.loki.dataDir}/compactor";
              retention_enabled = true;
              delete_request_store = "filesystem";
            };
            limits_config = {
              retention_period = cfg.logRetention;
              ingestion_rate_mb = 8;
              ingestion_burst_size_mb = 16;
              max_query_parallelism = 4;
              split_queries_by_interval = "24h";
            };
          };
        };
        services.prometheus = {
          enable = true;
          listenAddress = "127.0.0.1";
          retentionTime = cfg.metricsRetention;
          extraFlags = [ "--storage.tsdb.retention.size=${cfg.metricsSize}" ];
          globalConfig.scrape_interval = "30s";
          scrapeConfigs = [
            {
              job_name = "node";
              static_configs = map (host: {
                targets = [
                  (
                    if host == "${config.networking.hostName}.${suffix}" then
                      "127.0.0.1:${toString config.telemetry.metricsBackendPort}"
                    else
                      "${host}:${toString config.telemetry.metricsPort}"
                  )
                ];
                labels.host = lib.head (lib.splitString "." host);
              }) cfg.clients;
            }
            {
              job_name = "collector";
              static_configs = [ { targets = [ "127.0.0.1:9090" ]; } ];
            }
          ];
        };
        services.grafana = {
          enable = true;
          # Grafana 13 packages these data sources separately from its core.
          declarativePlugins = with pkgs.grafanaPlugins; [
            loki
            prometheus
          ];
          settings = {
            server = {
              http_addr = "127.0.0.1";
              http_port = cfg.grafanaBackendPort;
              root_url = cfg.publicUrl;
            };
            security = {
              admin_user = "admin";
              admin_password = "$__file{${passwordFile}}";
              secret_key = "$__file{${secretFile}}";
            };
            users.allow_sign_up = false;
            "auth.anonymous".enabled = false;
            analytics = {
              reporting_enabled = false;
              check_for_updates = false;
              check_for_plugin_updates = false;
            };
            smtp.enabled = false;
            plugins.preinstall_disabled = true;
            "unified_alerting.state_history" = {
              enabled = true;
              backend = "loki";
              loki_remote_url = "http://127.0.0.1:${toString cfg.lokiPort}";
            };
          };
          provision = {
            enable = true;
            datasources.settings.datasources = [
              {
                name = "Logs";
                uid = "telemetry-loki";
                type = "loki";
                access = "proxy";
                url = "http://127.0.0.1:${toString cfg.lokiPort}";
                isDefault = true;
              }
              {
                name = "Metrics";
                uid = "telemetry-prometheus";
                type = "prometheus";
                access = "proxy";
                url = "http://127.0.0.1:9090";
              }
            ];
            dashboards.settings.providers = [
              {
                name = "telemetry";
                options.path = self.data.path "features/telemetry/dashboards";
              }
            ];
            alerting = {
              rules.settings = alerts;
              contactPoints.settings.contactPoints = [
                {
                  orgId = 1;
                  name = "inbox";
                  receivers = [
                    {
                      uid = "telemetry-inbox";
                      type = "email";
                      settings.addresses = "telemetry@localhost";
                    }
                  ];
                }
              ];
              # Root policies cannot be muted. The catch-all child consumes all
              # notifications while evaluation and Loki state history continue.
              policies.settings.policies = [
                {
                  orgId = 1;
                  receiver = "inbox";
                  group_by = [
                    "grafana_folder"
                    "alertname"
                    "host"
                    "unit"
                  ];
                  routes = [
                    {
                      receiver = "inbox";
                      mute_time_intervals = [ "inbox-only" ];
                    }
                  ];
                }
              ];
              muteTimings.settings.muteTimes = [
                {
                  orgId = 1;
                  name = "inbox-only";
                  time_intervals = [
                    {
                      times = [
                        {
                          start_time = "00:00";
                          end_time = "24:00";
                        }
                      ];
                    }
                  ];
                }
              ];
            };
          };
        };
        systemd.services.grafana.serviceConfig.ExecStartPre = [ initSecrets ];
        systemd.services.loki.serviceConfig = {
          ProtectSystem = lib.mkForce "strict";
          ReadOnlyPaths = [ "/run" ];
          ReadWritePaths = [ config.services.loki.dataDir ];
          PrivateDevices = true;
          CapabilityBoundingSet = "";
        };
      };
    };
}
