/**
  Journal collection and host metrics, with interface-bound tailnet ingress.

  Fleet defaults select the collector without evaluating another host. Importing
  this feature does nothing until telemetry.enable is set. The server uses the
  same client and contributes private listeners; extraConfig extends Alloy.
  See docs/telemetry.md for the trust boundary and operational limits.
*/
{ config, self, ... }:
let
  fleet = config.flake.fleet;
  server = "${fleet.telemetry.server}.${fleet.tailnets.${fleet.telemetry.tailnet}.dnsSuffix}";
in
{
  flake.modules.nixos.telemetry =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.telemetry;
      device = "sys-subsystem-net-devices-${lib.replaceStrings [ "-" ] [ "\\x2d" ] cfg.interface}.device";
      listeners = lib.mapAttrs' (name: value: lib.nameValuePair "telemetry-${name}" value) cfg.listeners;
      alloyConfig = pkgs.writeText "telemetry.alloy" (
        lib.replaceStrings
          [ "@hostname@" "@pushUrl@" ]
          [ (builtins.toJSON config.networking.hostName) (builtins.toJSON cfg.pushUrl) ]
          (self.data.read "features/telemetry/journal.alloy")
        + "\n"
        + cfg.extraConfig
      );
    in
    {
      key = "flake.modules.nixos.telemetry";
      options.telemetry = {
        enable = lib.mkEnableOption "journal and host telemetry";
        interface = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "tailscale0";
          description = "Interface allowed to reach telemetry listeners.";
        };
        pushUrl = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "http://${server}:${toString fleet.ports.shared.telemetry-ingress}/loki/api/v1/push";
          description = "Loki-compatible ingestion URL, normally over the tailnet.";
        };
        metricsPort = lib.mkOption {
          type = lib.types.port;
          default = fleet.ports.shared.telemetry-metrics;
          description = "Interface-bound node exporter port.";
        };
        metricsBackendPort = lib.mkOption {
          type = lib.types.port;
          default = 19100;
          description = "Loopback-only node exporter port.";
        };
        alloyHttpPort = lib.mkOption {
          type = lib.types.port;
          default = 12345;
          description = "Loopback-only Alloy HTTP port.";
        };
        extraConfig = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Additional Alloy components merged into the client instance.";
        };
        listeners = lib.mkOption {
          internal = true;
          default = { };
          description = "Interface-bound socket proxies contributed by telemetry components.";
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                port = lib.mkOption { type = lib.types.port; };
                backendPort = lib.mkOption { type = lib.types.port; };
              };
            }
          );
        };
      };
      config = lib.mkIf cfg.enable {
        telemetry.listeners.metrics = {
          port = cfg.metricsPort;
          backendPort = cfg.metricsBackendPort;
        };
        services.alloy = {
          enable = true;
          # Temporary fix for marked-but-still-writable WAL segments. Keep this
          # local until upstream fixes it; see docs/research/alloy-wal-completion.md.
          package = lib.mkDefault (
            assert lib.assertMsg (pkgs.grafana-alloy.version == "1.21.3")
              "Revalidate the telemetry WAL patch and regressions before updating Alloy.";
            pkgs.grafana-alloy.overrideAttrs (old: {
              # nixpkgs uses an explicit patchPhase without the normal patches hook.
              patchPhase = old.patchPhase + ''
                patch -p1 < ${builtins.toFile "alloy-wal-completion.patch" (
                  self.data.read "features/telemetry/alloy-wal-completion.patch"
                )}
              '';
            })
          );
          configPath = alloyConfig;
          extraFlags = [
            "--disable-reporting"
            # Loki WAL is runtime-gated as experimental in the pinned Alloy.
            "--stability.level=experimental"
            "--server.http.listen-addr=127.0.0.1:${toString cfg.alloyHttpPort}"
          ];
        };
        services.prometheus.exporters.node = {
          enable = true;
          listenAddress = "127.0.0.1";
          port = cfg.metricsBackendPort;
          enabledCollectors = [ "systemd" ];
        };
        networking.firewall.interfaces.${cfg.interface}.allowedTCPPorts = map (v: v.port) (
          builtins.attrValues listeners
        );
        # Device activation starts listeners, including after an interface is
        # recreated. No dependency on sockets.target: a missing VPN must not
        # hold up boot before tailscaled can create the interface.
        systemd.sockets = lib.mapAttrs (_: value: {
          wantedBy = [ device ];
          socketConfig = {
            ListenStream = "${if config.networking.enableIPv6 then "[::]" else "0.0.0.0"}:${toString value.port}";
            BindToDevice = cfg.interface;
          } // lib.optionalAttrs config.networking.enableIPv6 {
            BindIPv6Only = "both";
          };
        }) listeners;
        systemd.services =
          lib.mapAttrs (name: value: {
            requires = [ "${name}.socket" ];
            bindsTo = [ "${name}.socket" ];
            after = [ "${name}.socket" ];
            serviceConfig = {
              ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${toString value.backendPort}";
              DynamicUser = true;
              NoNewPrivileges = true;
              PrivateTmp = true;
              PrivateDevices = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              RestrictAddressFamilies = [
                "AF_INET"
                "AF_INET6"
              ];
              CapabilityBoundingSet = "";
            };
          }) listeners
          // {
            # switch-to-configuration restarts active targets, not device units.
            # Start new listeners on rebuild too, without waiting for a VPN
            # that has not yet appeared or introducing an early-boot cycle.
            telemetry-listeners = {
              wantedBy = [ "multi-user.target" ];
              unitConfig.ConditionPathExists = "/sys/class/net/${cfg.interface}";
              restartTriggers = [
                (builtins.toJSON cfg.listeners)
                cfg.interface
              ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script = "${pkgs.systemd}/bin/systemctl --no-block start ${
                lib.escapeShellArgs (map (name: "${name}.socket") (builtins.attrNames listeners))
              }";
            };
            alloy.serviceConfig = {
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              PrivateDevices = true;
              NoNewPrivileges = true;
              ReadOnlyPaths = [ "/run" ];
              CapabilityBoundingSet = "";
            };
          };
      };
    };
}
