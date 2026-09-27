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
      printf 'base_url=%s\ncontext_limit=%s\ntool_search=%s\nguard=%s\n' \
        "''${ANTHROPIC_BASE_URL:-}" "''${CC_CONTEXT_LIMIT:-}" \
        "''${ENABLE_TOOL_SEARCH:-}" "''${AGENT_CONTEXT_GUARD:-}" > "$AGENT_TEST_URL"
    '')
    // {
      version = "2.1.280";
    };
  configuration = inputs.unstable-home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      inputs.self.modules.homeManager.claude-code
      inputs.self.modules.homeManager.codex
      {
        home = {
          username = "agent-fixture";
          homeDirectory = "/home/agent-fixture";
          stateVersion = "24.11";
        };
        programs.claude-code.package = mockClient "claude";
        programs.codex.package = mockClient "codex";
        services.tokview.enable = false;
      }
    ];
  };
  cfg = configuration.config;
  wrappers = builtins.filter (
    package:
    builtins.elem package.name [
      "cc"
      "cc-native"
      "cx"
      "cx-native"
    ]
  ) cfg.home.packages;
  names = map (package: package.name) cfg.home.packages;
  wrapper = name: builtins.head (builtins.filter (package: package.name == name) wrappers);
  events = [
    "PostToolUse"
    "Stop"
    "SessionStart"
    "PreCompact"
  ];
  guardState =
    enabled:
    "hooks.state={"
    + pkgs.lib.concatMapStringsSep ", " (
      key: "${builtins.toJSON key}={enabled=${enabled}}"
    ) inputs.self.lib.agents.codexGuardHookKeys
    + "}";
in
assert builtins.length wrappers == 4;
assert
  !(builtins.any (name: builtins.elem name names) [
    "ccs"
    "ccs-native"
    "cxs"
    "cxs-native"
  ]);
assert builtins.all (event: builtins.hasAttr event cfg.programs.claude-code.settings.hooks) events;
assert builtins.all (
  key: !cfg.programs.codex.settings.hooks.state.${key}.enabled
) inputs.self.lib.agents.codexGuardHookKeys;
assert !(builtins.hasAttr ".serena-cxs/serena_config.yml" cfg.home.file);
pkgs.runCommand "agent-wrappers-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  for wrapper in ${
    pkgs.lib.escapeShellArgs (map (package: "${package}/bin/${package.name}") wrappers)
  }; do
    if grep -qiE "serena|headroom" "$wrapper"; then
      echo "unexpected removed dependency in $wrapper" >&2
      exit 1
    fi
  done
  ${pkgs.lib.concatMapStringsSep "\n" (package: ''
    ${package}/bin/${package.name} --${
      if pkgs.lib.hasPrefix "cc" package.name then "cc" else "cx"
    }-help > /dev/null
  '') wrappers}

  export AGENT_TEST_ARGS="$PWD/args"
  export AGENT_TEST_URL="$PWD/environment"
  ${wrapper "cc-native"}/bin/cc-native sonnet 1m search skills plan -- 'literal prompt'
  grep -Fx 'sonnet[1m]' "$AGENT_TEST_ARGS"
  grep -F 'EnterPlanMode' "$AGENT_TEST_ARGS"
  grep -F 'Skill' "$AGENT_TEST_ARGS"
  grep -Fx 'literal prompt' "$AGENT_TEST_ARGS"
  grep -Fx 'context_limit=1000000' "$AGENT_TEST_URL"
  grep -Fx 'tool_search=auto' "$AGENT_TEST_URL"
  grep -Fx 'guard=0' "$AGENT_TEST_URL"
  if grep -Fx -- '--autocompact' "$AGENT_TEST_ARGS"; then
    echo 'unguarded Claude changed auto-compaction' >&2
    exit 1
  fi

  ${wrapper "cc-native"}/bin/cc-native guard
  grep -Fx 'guard=1' "$AGENT_TEST_URL"
  grep -Fx -- '--autocompact' "$AGENT_TEST_ARGS"
  grep -Fx '1M' "$AGENT_TEST_ARGS"
  AGENT_CONTEXT_GUARD=1 ${wrapper "cc-native"}/bin/cc-native -- guard
  grep -Fx 'guard=0' "$AGENT_TEST_URL"
  grep -Fx 'guard' "$AGENT_TEST_ARGS"

  ${wrapper "cc-native"}/bin/cc-native 1m -- --model=sonnet
  grep -Fx -- '--model=sonnet[1m]' "$AGENT_TEST_ARGS"
  if ${wrapper "cc-native"}/bin/cc-native graph; then
    echo 'retired graph selector unexpectedly succeeded' >&2
    exit 1
  fi

  ${wrapper "cx-native"}/bin/cx-native astra hi -- sol
  grep -Fx 'gpt-6-astra' "$AGENT_TEST_ARGS"
  grep -Fx 'model_reasoning_effort="high"' "$AGENT_TEST_ARGS"
  grep -Fx 'sol' "$AGENT_TEST_ARGS"
  grep -Fx ${pkgs.lib.escapeShellArg (guardState "false")} "$AGENT_TEST_ARGS"
  ${wrapper "cx-native"}/bin/cx-native guard
  grep -Fx ${pkgs.lib.escapeShellArg (guardState "true")} "$AGENT_TEST_ARGS"
  python3 - <<'PY'
  import pathlib
  import tomllib
  argument = next(line for line in pathlib.Path('args').read_text().splitlines()
                  if line.startswith('hooks.state='))
  states = tomllib.loads(argument)['hooks']['state']
  assert len(states) == 4
  assert all(key.startswith('/etc/codex/config.toml:') for key in states)
  assert all(state['enabled'] is True for state in states.values())
  PY
  ${wrapper "cx-native"}/bin/cx-native -- guard
  grep -Fx ${pkgs.lib.escapeShellArg (guardState "false")} "$AGENT_TEST_ARGS"
  grep -Fx 'guard' "$AGENT_TEST_ARGS"
  touch "$out"
''
