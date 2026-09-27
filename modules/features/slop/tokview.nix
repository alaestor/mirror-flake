/**
  Local token observability for coding-agent sessions. Both harnesses use one
  on-demand proxy per environment; it observes traffic without compressing context.
*/
{ inputs, self, ... }:
{
  flake.modules.homeManager.tokview =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.tokview;
      configFile = (pkgs.formats.yaml { }).generate "tokview-config.yaml" {
        proxy = {
          bind = "127.0.0.1";
          port = cfg.proxyPort;
        };
        dashboard = {
          bind = "127.0.0.1";
          port = cfg.dashboardPort;
        };
        storage.path = "${config.home.homeDirectory}/.tokview/db.sqlite";
        capture = {
          prompts = false;
          responses = false;
        };
      };
      daemon = pkgs.writeShellScript "tokview-daemon" ''
        # Include the managed config in the unit identity so changes restart it.
        # ${configFile}
        exec ${lib.getExe cfg.package} start --foreground
      '';
      session = pkgs.writeShellApplication {
        name = "tokview-session";
        runtimeInputs = [
          pkgs.systemd
          pkgs.curl
        ];
        text = ''
          # The guest runs no Home Manager. Its SQLite state stays local, and
          # this link is the only declarative file recreated on session entry.
          if [[ "''${AGENT_VM_GUEST:-}" == 1 ]]; then
            ${pkgs.coreutils}/bin/mkdir -p "$HOME/.tokview"
            ${pkgs.coreutils}/bin/ln -sfn ${lib.escapeShellArg configFile} "$HOME/.tokview/config.yaml"
          fi

          if ! systemctl --user --quiet is-active tokview.service; then
            if systemctl --user --quiet cat tokview.service >/dev/null 2>&1; then
              systemctl --user start tokview.service
            else
              systemd-run --user --quiet --collect \
                --unit=tokview.service \
                --property=Restart=on-failure \
                --property=RestartSec=2 \
                --setenv=TOKVIEW_INTERNAL_SPAWN=1 \
                ${daemon} \
                || systemctl --user --quiet is-active tokview.service
            fi
          fi

          deadline=$((SECONDS+30))
          while (( SECONDS < deadline )); do
            if curl --silent --fail --max-time 1 \
              http://127.0.0.1:${toString cfg.dashboardPort}/api/health >/dev/null \
              && (exec 3<>/dev/tcp/127.0.0.1/${toString cfg.proxyPort}) 2>/dev/null; then
              exec "$@"
            fi
            if ! systemctl --user --quiet is-active tokview.service; then
              echo 'tokview failed to start; inspect journalctl --user -u tokview.service' >&2
              exit 1
            fi
            sleep 0.1
          done
          echo 'tokview did not become ready; refusing an unobserved session' >&2
          exit 1
        '';
      };
      guestCli = pkgs.writeShellApplication {
        name = "tokview-guest";
        text = self.lib.agents.mkVmSandbox pkgs {
          name = "tokview-guest";
          native = cfg.package;
          helpFlag = "--help";
        };
      };
    in
    {
      key = "flake.modules.homeManager.tokview";
      options.services.tokview = {
        enable = lib.mkEnableOption "local token observability for coding agents";
        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.alpkgs.packages.${pkgs.stdenv.hostPlatform.system}.tokview;
          description = "Tokview CLI and proxy package.";
        };
        proxyPort = lib.mkOption {
          type = lib.types.port;
          default = 4000;
          description = "Loopback port for the provider-compatible proxy.";
        };
        dashboardPort = lib.mkOption {
          type = lib.types.port;
          default = 3000;
          description = "Loopback port for the dashboard and health endpoint.";
        };
        sessionLauncher = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          default = session;
          description = "Internal launcher that waits for the proxy before executing a session.";
        };
      };
      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.proxyPort != cfg.dashboardPort;
            message = "Tokview proxy and dashboard ports must differ.";
          }
        ];
        home.packages = [
          cfg.package
          guestCli
        ];
        home.file.".tokview/config.yaml".source = configFile;
        systemd.user.services.tokview = {
          Unit.Description = "Coding-agent token observability";
          Service = {
            Environment = "TOKVIEW_INTERNAL_SPAWN=1";
            ExecStart = toString daemon;
            Restart = "on-failure";
            RestartSec = 2;
          };
        };
      };
    };
}
