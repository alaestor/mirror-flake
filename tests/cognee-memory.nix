{ inputs, pkgs, ... }:
let
  mockSystemd = pkgs.symlinkJoin {
    name = "memory-systemd-fixture";
    paths = [
      (pkgs.writeShellScriptBin "systemctl" ''
        case "$*" in
          *is-active*) test -f "$AGENT_TEST_RUNNING" ;;
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
  python = pkgs.python313.withPackages (ps: [
    ps.mcp
    ps.aiohttp
  ]);
  cfg =
    (inputs.unstable-home-manager.lib.homeManagerConfiguration {
      pkgs = pkgs.extend (
        _: prev: {
          systemd = mockSystemd // {
            inherit (prev.systemd) override;
          };
        }
      );
      modules = [
        inputs.self.modules.homeManager.cognee-memory
        {
          home = {
            username = "memory-fixture";
            homeDirectory = "/home/memory-fixture";
            stateVersion = "24.11";
          };
          services.cognee-memory = {
            enable = true;
            package = pkgs.writeShellScriptBin "python" "exit 1";
            port = 48010;
            llmEndpoint = "http://127.0.0.1:48011/v1";
            llmModel = "test-model";
            stateDirectory = "/build/cognee-memory";
          };
        }
      ];
    }).config;
in
assert !(cfg.systemd.user.services.cognee-memory ? Install);
pkgs.runCommand "cognee-memory-test"
  {
    nativeBuildInputs = [
      python
      pkgs.curl
    ];
  }
  ''
    export AGENT_TEST_RUNNING="$PWD/running"
    export AGENT_TEST_EVENTS="$PWD/events"
    touch "$AGENT_TEST_EVENTS"
    python ${inputs.self.data.path "agents/cognee-memory/test-server.py"}
    python ${inputs.self.data.path "agents/cognee-memory/test-integration.py"} \
      ${pkgs.lib.getExe cfg.services.cognee-memory.sessionPrepare} \
      ${pkgs.lib.getExe cfg.services.cognee-memory.mcpBridge}
    touch "$out"
  ''
