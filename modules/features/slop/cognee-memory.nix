/**
  Opt-in text memory shared by coding harnesses. Cognee owns host-local storage;
  stdio MCP clients expose only text memory and single-item deletion, not host file ingestion.
  The user service starts on demand and is not wanted by a login target.
*/
{
  inputs,
  self,
  lib,
  ...
}:
{
  flake.lib.agents.cogneeInstructions = ''
    Cognee memory is enabled. Recall relevant prior decisions before starting work.
    Save concise verified facts and decisions, not transcripts or secrets. Use project
    scope for repository facts and global scope for preferences that apply across
    projects. Recall defaults to both scopes. Claude and Codex share this memory.
  '';
  flake.lib.agents.cogneeSandboxText =
    pkgs: config:
    let
      cfg = config.services.cognee-memory;
    in
    ''
      session_args=()
      session_environment=()
      for argument in "$@"; do
        case "$argument" in
          --) break ;;
          mem|memory)
            ${
              if cfg.enable then
                ''
                  COGNEE_MEMORY_REMOTE=0 COGNEE_MEMORY_URL="" ${lib.getExe cfg.sessionPrepare}
                  memory_port="$(${pkgs.coreutils}/bin/shuf -i 20000-60000 -n 1)"
                  session_args+=( --reverse-forward "127.0.0.1:$memory_port:127.0.0.1:${toString cfg.port}" )
                  session_environment+=( COGNEE_MEMORY_REMOTE=1 "COGNEE_MEMORY_URL=http://127.0.0.1:$memory_port" )
                ''
              else
                ''
                  echo 'cognee: memory is disabled in this configuration' >&2
                  exit 1
                ''
            }
            break
            ;;
        esac
      done
    '';
  flake.modules.homeManager.cognee-memory =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.cognee-memory;
      url = "http://127.0.0.1:${toString cfg.port}";
      mcpPython = pkgs.python313.withPackages (ps: [ ps.mcp ]);
      bridge = pkgs.writeShellApplication {
        name = "cognee-memory-mcp";
        runtimeInputs = [ pkgs.git ];
        text = ''
          exec ${mcpPython}/bin/python ${self.data.path "agents/cognee-memory/bridge.py"} --url "''${COGNEE_MEMORY_URL:-${url}}"
        '';
      };
      daemon = pkgs.writeShellScript "cognee-memory-daemon" ''
        export COGNEE_MEMORY_PORT=${toString cfg.port}
        export COGNEE_LLM_ENDPOINT=${lib.escapeShellArg cfg.llmEndpoint}
        export COGNEE_LLM_MODEL="$(${pkgs.curl}/bin/curl --silent --fail --max-time 5 "$COGNEE_LLM_ENDPOINT/models" | ${pkgs.jq}/bin/jq --exit-status --raw-output '.data[0].id | select(type == "string" and length > 0)')" || exit 1
        export LLM_PROVIDER=openai
        export LLM_MODEL="openai/$COGNEE_LLM_MODEL"
        export LLM_ENDPOINT="$COGNEE_LLM_ENDPOINT"
        # Cognee/OpenAI require a nonempty value; this is not a credential.
        export LLM_API_KEY=local
        export STRUCTURED_OUTPUT_FRAMEWORK=instructor
        export LLM_INSTRUCTOR_MODE=json_schema_mode
        export EMBEDDING_PROVIDER=fastembed
        export EMBEDDING_MODEL=BAAI/bge-small-en-v1.5
        export FASTEMBED_CACHE_PATH=${lib.escapeShellArg "${cfg.stateDirectory}/embeddings"}
        export HF_HOME=${lib.escapeShellArg "${cfg.stateDirectory}/huggingface"}
        export DATA_ROOT_DIRECTORY=${lib.escapeShellArg "${cfg.stateDirectory}/data"}
        export SYSTEM_ROOT_DIRECTORY=${lib.escapeShellArg "${cfg.stateDirectory}/system"}
        export CACHE_ROOT_DIRECTORY=${lib.escapeShellArg "${cfg.stateDirectory}/cache"}
        export COGNEE_LOGS_DIR=${lib.escapeShellArg "${cfg.stateDirectory}/logs"}
        export COGNEE_REPOS_DIR=${lib.escapeShellArg "${cfg.stateDirectory}/repos"}
          export TELEMETRY_DISABLED=1 COGNEE_TRACING_ENABLED=false AUTO_FEEDBACK=false
          export KUZU_BUFFER_POOL_SIZE=134217728 KUZU_NUM_THREADS=2
          umask 077
          mkdir -p ${lib.escapeShellArg cfg.stateDirectory}
          cd ${lib.escapeShellArg cfg.stateDirectory}
        exec ${cfg.package}/bin/python ${self.data.path "agents/cognee-memory/server.py"}
      '';
      prepare = pkgs.writeShellApplication {
        name = "cognee-memory-prepare";
        runtimeInputs = [
          pkgs.curl
          pkgs.jq
          pkgs.systemd
          pkgs.coreutils
        ];
        text = ''
          if [[ "''${COGNEE_MEMORY_REMOTE:-0}" != 1 ]]; then
            model="$(curl --silent --fail --max-time 5 ${lib.escapeShellArg "${cfg.llmEndpoint}/models"} \
              | jq --exit-status --raw-output '.data[0].id | select(type == "string" and length > 0)')" || {
              echo 'cognee: local LLM unavailable at ${cfg.llmEndpoint}' >&2
              exit 1
            }
            if systemctl --user --quiet is-active cognee-memory.service; then
              active_model="$(curl --silent --fail --max-time 5 ${url}/health | jq --raw-output '.model // empty' || true)"
              if [[ "$active_model" != "$model" ]]; then
                systemctl --user restart cognee-memory.service >/dev/null 2>&1 || {
                  echo 'cognee: memory service failed to restart' >&2; exit 1;
                }
              fi
            fi
            if ! systemctl --user --quiet is-active cognee-memory.service; then
              if systemctl --user --quiet cat cognee-memory.service >/dev/null 2>&1; then
                systemctl --user start cognee-memory.service >/dev/null 2>&1 || {
                  echo 'cognee: memory service failed to start' >&2; exit 1;
                }
              else
                systemd-run --user --quiet --collect --unit=cognee-memory.service \
                  --property=UMask=0077 --property=NoNewPrivileges=yes ${daemon} >/dev/null 2>&1 \
                  || systemctl --user --quiet is-active cognee-memory.service || {
                    echo 'cognee: memory service failed to start' >&2; exit 1;
                  }
              fi
            fi
          fi
          memory_url="''${COGNEE_MEMORY_URL:-${url}}"
          deadline=$((SECONDS+30))
          while (( SECONDS < deadline )); do
            response="$(curl --silent --write-out $'\n%{http_code}' --max-time 12 "$memory_url/health" || true)"
            status="''${response##*$'\n'}"
            case "$status" in
              200)
                if jq --exit-status '.ready == true' <<< "''${response%$'\n'*}" >/dev/null 2>&1; then
                  exit 0
                fi
                echo 'cognee: memory service unavailable' >&2; exit 1 ;;
              503) echo 'cognee: local LLM unavailable at ${cfg.llmEndpoint}' >&2; exit 1 ;;
            esac
            sleep 0.1
          done
          echo 'cognee: memory service unavailable' >&2
          exit 1
        '';
      };
    in
    {
      key = "flake.modules.homeManager.cognee-memory";
      options.services.cognee-memory = {
        enable = lib.mkEnableOption "opt-in host-local Cognee memory";
        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.alpkgs.packages.${pkgs.stdenv.hostPlatform.system}.cognee;
          description = "Cognee SDK environment used by the host service.";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 8765;
          description = "Loopback port for the host memory API.";
        };
        llmEndpoint = lib.mkOption {
          type = lib.types.str;
          default = "http://localhost:1234/v1";
          description = "Host-local OpenAI-compatible LLM endpoint, without a trailing slash; the first advertised model is used.";
        };
        stateDirectory = lib.mkOption {
          type = lib.types.str;
          default = "${config.home.homeDirectory}/.local/share/cognee-memory";
          description = "Private host-local Cognee databases and model caches; never shared into the guest.";
        };
        mcpBridge = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          default = bridge;
          description = "Text-only stdio MCP adapter.";
        };
        sessionPrepare = lib.mkOption {
          type = lib.types.package;
          default = prepare;
          description = "Launcher preflight, overridable by test fixtures.";
        };
      };
      config = lib.mkIf cfg.enable {
        systemd.user.services.cognee-memory = {
          Unit.Description = "Shared coding-agent text memory";
          Service = {
            ExecStart = toString daemon;
            UMask = "0077";
            NoNewPrivileges = true;
            TimeoutStopSec = 30;
          };
        };
      };
    };
}
