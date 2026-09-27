{ inputs, pkgs, ... }:
let
  mockClient =
    name:
    (pkgs.writeShellScriptBin name ''
      if [[ "''${1:-}" == --version ]]; then
        echo '2.1.280'
        exit 0
      fi
      printf '%s\n' "$@" > "$AGENT_TEST_ARGS"
      printf '%s\n' "''${ANTHROPIC_BASE_URL:-}" > "$AGENT_TEST_URL"
    '')
    // {
      version = "2.1.280";
    };
  mockSystemd = pkgs.symlinkJoin {
    name = "mock-tokview-systemd";
    paths = [
      (pkgs.writeShellScriptBin "systemctl" ''
        case "$*" in
          *is-active*) [[ "''${AGENT_TEST_STOPPED:-0}" != 1 && -f "$AGENT_TEST_RUNNING" ]] ;;
          *cat*) [[ "''${AGENT_TEST_TRANSIENT:-0}" != 1 ]] ;;
          *start*) echo start >> "$AGENT_TEST_EVENTS"; touch "$AGENT_TEST_RUNNING" ;;
          *) exit 2 ;;
        esac
      '')
      (pkgs.writeShellScriptBin "systemd-run" ''
        echo transient >> "$AGENT_TEST_EVENTS"
        touch "$AGENT_TEST_RUNNING"
      '')
    ];
  };
  configuration = inputs.unstable-home-manager.lib.homeManagerConfiguration {
    pkgs = pkgs.extend (
      _final: _prev: {
        systemd = mockSystemd;
      }
    );
    modules = [
      inputs.self.modules.homeManager.claude-code
      inputs.self.modules.homeManager.codex
      {
        home = {
          username = "token-fixture";
          homeDirectory = "/home/token-fixture";
          stateVersion = "24.11";
        };
        programs.claude-code.package = mockClient "claude";
        programs.codex.package = mockClient "codex";
        services.tokview = {
          proxyPort = 48000;
          dashboardPort = 48001;
        };
      }
    ];
  };
  cfg = configuration.config;
  wrapper = name: builtins.head (builtins.filter (package: package.name == name) cfg.home.packages);
  contributions = inputs.self.lib.agents.vmContributionsFor "/home/token-fixture" [ "tokview" ];
in
assert cfg.services.tokview.enable;
assert builtins.attrNames cfg.systemd.user.services == [ "tokview" ];
assert contributions.stateDirs == [ ];
assert map (entry: entry.path) contributions.localStateDirs == [ "/home/token-fixture/.tokview" ];
pkgs.runCommand "tokview-integration-test"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.curl
    ];
  }
  ''
    export AGENT_TEST_ARGS="$PWD/args"
    export AGENT_TEST_URL="$PWD/url"
    export AGENT_TEST_RUNNING="$PWD/running"
    export AGENT_TEST_EVENTS="$PWD/events"
    touch "$AGENT_TEST_EVENTS"

    python3 - <<'PY' &
    import http.server
    import pathlib
    import threading
    import time
    class Health(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(503 if pathlib.Path('unhealthy').exists() else 200)
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')
        def log_message(self, *args):
            pass
    for port in (48000, 48001):
        server = http.server.ThreadingHTTPServer(('127.0.0.1', port), Health)
        threading.Thread(target=server.serve_forever, daemon=True).start()
    while True:
        time.sleep(1)
    PY
    server_pid=$!
    trap 'kill "$server_pid"' EXIT

    sha256sum ${cfg.home.file.".codex/config.toml".source} > before
    ${wrapper "cx-native"}/bin/cx-native luna -- 'literal prompt'
    grep -Fx 'gpt-6-luna' "$AGENT_TEST_ARGS"
    grep -Fx 'openai_base_url="http://127.0.0.1:48000/v1"' "$AGENT_TEST_ARGS"
    grep -Fx 'literal prompt' "$AGENT_TEST_ARGS"

    ${wrapper "cc-native"}/bin/cc-native opus hi -- 'another prompt'
    grep -Fx 'opus' "$AGENT_TEST_ARGS"
    grep -Fx 'another prompt' "$AGENT_TEST_ARGS"
    grep -Fx 'http://127.0.0.1:48000' "$AGENT_TEST_URL"
    test "$(grep -c '^start$' "$AGENT_TEST_EVENTS")" = 1
    sha256sum ${cfg.home.file.".codex/config.toml".source} > after
    cmp before after

    rm "$AGENT_TEST_RUNNING"
    AGENT_TEST_TRANSIENT=1 ${wrapper "cx-native"}/bin/cx-native terra
    grep -Fx transient "$AGENT_TEST_EVENTS"
    grep -Fx 'gpt-6-terra' "$AGENT_TEST_ARGS"

    echo untouched > "$AGENT_TEST_ARGS"
    touch unhealthy
    if AGENT_TEST_STOPPED=1 ${wrapper "cx-native"}/bin/cx-native; then
      echo 'session unexpectedly launched with an unhealthy proxy' >&2
      exit 1
    fi
    grep -Fx untouched "$AGENT_TEST_ARGS"
    touch "$out"
  ''
