{ inputs, pkgs, ... }:
let
  agents = inputs.self.lib.agents;
  directivePackage = agents.directives pkgs;
  directiveHook = agents.codexDirectiveHook pkgs;
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
      if [[ ${pkgs.lib.escapeShellArg name} == codex ]]; then
        printf '%s\n' "''${AGENT_DIRECTIVES_BIN:-}" > "$AGENT_TEST_DIRECTIVES"
      fi
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
      }
    ];
  };
  cfg = configuration.config;
  profiles = import (inputs.self.data.path "agents/subagent-profiles.nix");
  expectedRoles = pkgs.writeText "expected-agent-roles.json" (builtins.toJSON {
    roles = (import (inputs.self.data.path "programs/codex/agents.nix") { inherit profiles; }).roles;
    shell = agents.fragments.shell pkgs;
  });
  wrappers = builtins.filter (
    package:
    builtins.elem package.name [
      "cc"
      "cc-native"
      "cx"
      "cx-native"
    ]
  ) cfg.home.packages;
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
assert builtins.all (event: builtins.hasAttr event cfg.programs.claude-code.settings.hooks) events;
assert builtins.hasAttr "UserPromptSubmit" cfg.programs.claude-code.settings.hooks;
assert builtins.all (
  key: !cfg.programs.codex.settings.hooks.state.${key}.enabled
) inputs.self.lib.agents.codexGuardHookKeys;
assert cfg.programs.codex.skills == agents.skills;
assert cfg.programs.claude-code.skills == agents.skills;
assert builtins.all (path: builtins.pathExists "${path}/SKILL.md") (
  builtins.attrValues agents.skills
);
assert pkgs.lib.count (path: path == "/home/fixture/.agents/memory") (
  agents.stateDirsFor "/home/fixture" [ "claude" "codex" ]
) == 1;
pkgs.runCommand "agent-wrappers-test" { nativeBuildInputs = [ pkgs.python3 pkgs.git ]; } ''
  ${pkgs.lib.concatMapStringsSep "\n" (package: ''
    ${package}/bin/${package.name} --${
      if pkgs.lib.hasPrefix "cc" package.name then "cc" else "cx"
    }-help > /dev/null
  '') wrappers}

  export AGENT_TEST_ARGS="$PWD/args"
  export AGENT_TEST_URL="$PWD/environment"
  export AGENT_TEST_DIRECTIVES="$PWD/directives-path"
  # The isolated entry points must refuse an unshared cwd, never silently
  # falling back to the native client or starting a VM session.
  mkdir mock-bin
  cat > mock-bin/agent-vm-session <<'SH'
  #!${pkgs.python3}/bin/python3
  import json, os, pathlib, sys
  pathlib.Path(os.environ['AGENT_TEST_ARGS']).write_text(json.dumps({
      'cwd': os.getcwd(), 'argv': sys.argv[1:]}))
  sys.exit(int(os.environ.get('AGENT_TEST_SESSION_STATUS', '0')))
  SH
  chmod +x mock-bin/agent-vm-session
  for executable in ${wrapper "cc"}/bin/cc ${wrapper "cx"}/bin/cx; do
    if PATH="$PWD/mock-bin:$PATH" "$executable" >refused.out 2>refused.err; then
      echo 'isolated wrapper accepted an unshared directory' >&2
      exit 1
    fi
    grep -F 'outside every shared root' refused.err
    test ! -e "$AGENT_TEST_ARGS"
  done
  # Successful isolated dispatch must retain the exact cwd and argv and name
  # the native store executable, without executing that client on the host.
  export AGENT_TEST_HOME="$PWD/isolated-home"
  mkdir -p "$AGENT_TEST_HOME/Projects/two words/nested" "$AGENT_TEST_HOME/Projects-other"
  ${pkgs.lib.concatMapStringsSep "\n" (name: ''
    (
      cd "$AGENT_TEST_HOME/Projects/two words/nested"
      HOME="$AGENT_TEST_HOME" PATH="$NIX_BUILD_TOP/mock-bin:$PATH" \
        ${wrapper name}/bin/${name} -- 'two words' "" $'a\nline' '; touch /tmp/never-run'
    )
    python3 - <<'PY'
  import json, os, pathlib
  call = json.loads(pathlib.Path(os.environ['AGENT_TEST_ARGS']).read_text())
  cwd = os.environ['AGENT_TEST_HOME'] + '/Projects/two words/nested'
  assert call['cwd'] == cwd, call
  assert call['argv'] == ['--', '${pkgs.coreutils}/bin/env', '--chdir=' + cwd,
      '${wrapper "${name}-native"}/bin/${name}-native', '--', 'two words', "", 'a\nline', '; touch /tmp/never-run'], call
  assert not pathlib.Path(os.environ['AGENT_TEST_URL']).exists(), 'native fallback'
  PY
    rm "$AGENT_TEST_ARGS"
    (
      cd "$AGENT_TEST_HOME/Projects/two words/nested"
      set +e
      HOME="$AGENT_TEST_HOME" PATH="$NIX_BUILD_TOP/mock-bin:$PATH" \
        AGENT_TEST_SESSION_STATUS=73 ${wrapper name}/bin/${name} -- fixture
      test "$?" = 73
    )
    test ! -e "$AGENT_TEST_URL"
    rm "$AGENT_TEST_ARGS"
    (
      cd "$AGENT_TEST_HOME/Projects-other"
      if HOME="$AGENT_TEST_HOME" PATH="$NIX_BUILD_TOP/mock-bin:$PATH" \
        ${wrapper name}/bin/${name} 2> "$NIX_BUILD_TOP/refused.err"; then exit 1; fi
    )
    grep -F 'outside every shared root' refused.err
    test ! -e "$AGENT_TEST_ARGS"
  '') [ "cc" "cx" ]}
  ${wrapper "cc-native"}/bin/cc-native sonnet 1m search plan -- 'literal prompt'
  grep -Fx 'sonnet[1m]' "$AGENT_TEST_ARGS"
  grep -F 'EnterPlanMode' "$AGENT_TEST_ARGS"
  grep -Fx 'literal prompt' "$AGENT_TEST_ARGS"
  grep -Fx 'base_url=' "$AGENT_TEST_URL"
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
  ${wrapper "cx-native"}/bin/cx-native sol
  grep -Fx 'gpt-6.1-sol' "$AGENT_TEST_ARGS"
  ${wrapper "cx-native"}/bin/cx-native sol terra hi -- terra
  python3 - <<'PY'
  import pathlib
  args = pathlib.Path('args').read_text().splitlines()
  assert args[args.index('--model') + 1] == 'gpt-6.1-terra'
  assert 'gpt-6.1-sol' not in args
  assert 'model_reasoning_effort="high"' in args
  assert args[-1] == 'terra'
  PY
  ${wrapper "cx-native"}/bin/cx-native astra hi -- sol
  test "$(cat "$AGENT_TEST_DIRECTIVES")" = ${pkgs.lib.escapeShellArg (pkgs.lib.getExe directivePackage)}
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
  mkdir -p "$PWD/guest-home/.codex/skills"
  ln -s /nix/store/old-source/data/agents/skills/procedure/handoff "$PWD/guest-home/.codex/skills/procedure-handoff"
  ln -s /tmp/user-skill "$PWD/guest-home/.codex/skills/user-skill"
  HOME="$PWD/guest-home" AGENT_VM_GUEST=1 ${wrapper "cx-native"}/bin/cx-native
  test "$(cat "$AGENT_TEST_DIRECTIVES")" = ${pkgs.lib.escapeShellArg (pkgs.lib.getExe directivePackage)}
  test ! -L "$PWD/guest-home/.codex/skills/procedure-handoff"
  test -L "$PWD/guest-home/.codex/skills/user-skill"
  python3 - <<'PY'
  import json, pathlib, tomllib
  config = tomllib.loads(pathlib.Path('guest-home/.codex/config.toml').read_text())
  assert any(
      entry['path'] == '/home/agent-fixture/.codex/skills/.system/skill-creator/SKILL.md'
      and entry['enabled'] is False
      for entry in config['skills']['config']
  ), 'bundled skill-creator must stay disabled'
  expected = json.loads(pathlib.Path('${expectedRoles}').read_text())
  assert config['features']['multi_agent_v2'] is True
  assert set(config['agents']) == set(expected['roles'])
  for name, definition in expected['roles'].items():
      entry = config['agents'][name]
      assert entry['description'] == definition['description'], name
      role_path = pathlib.Path(entry['config_file'])
      assert str(role_path).startswith('/nix/store/')
      role = tomllib.loads(role_path.read_text())
      assert role['model'] == definition['model'], name
      assert role['model_reasoning_effort'] == definition['model_reasoning_effort'], name
      assert definition['developer_instructions'] in role['developer_instructions'], name
      assert expected['shell'] in role['developer_instructions'], name
  PY
  ${pkgs.lib.concatMapStringsSep "\n" (name: ''
    test "$(readlink "$PWD/guest-home/.codex/skills/${name}")" = ${pkgs.lib.escapeShellArg agents.skills.${name}}
  '') (builtins.attrNames agents.skills)}
  export XDG_STATE_HOME="$PWD/directive-state"
  printf '%s' '{"hook_event_name":"UserPromptSubmit","prompt":"^^handoff"}' \
    | AGENT_DIRECTIVES_BIN="$(cat "$AGENT_TEST_DIRECTIVES")" ${pkgs.lib.getExe directiveHook} > hook-output.json
  python3 - <<'PY'
  import json, pathlib, tomllib
  response = json.loads(pathlib.Path('hook-output.json').read_text())
  assert 'Write a local handoff' in response['hookSpecificOutput']['additionalContext']
  config = tomllib.loads(pathlib.Path('${agents.codexHookConfig pkgs}').read_text())
  command = config['hooks']['UserPromptSubmit'][0]['hooks'][0]['command']
  assert command == '${pkgs.lib.getExe directiveHook}'
  PY
  mkdir -p "$PWD/profile-home/.nix-profile/bin"
  ln -s ${pkgs.lib.getExe directivePackage} "$PWD/profile-home/.nix-profile/bin/agent-directives"
  printf '%s' '{"hook_event_name":"UserPromptSubmit","prompt":"^^handoff"}' \
    | env -u AGENT_DIRECTIVES_BIN HOME="$PWD/profile-home" ${pkgs.lib.getExe directiveHook} > fallback-output.json
  python3 - <<'PY'
  import json, pathlib
  assert 'Write a local handoff' in json.loads(pathlib.Path('fallback-output.json').read_text())['hookSpecificOutput']['additionalContext']
  PY
  if env -u AGENT_DIRECTIVES_BIN HOME="$PWD/profile-home" AGENT_VM_GUEST=1 ${pkgs.lib.getExe directiveHook} </dev/null 2> hook-error; then
    echo 'guest resolved a host Home Manager profile' >&2
    exit 1
  fi
  grep -F 'no Home Manager directive package' hook-error
  printf '#!/bin/sh\nexit 0\n' > "$PWD/writable-resolver"
  chmod +x "$PWD/writable-resolver"
  if AGENT_DIRECTIVES_BIN="$PWD/writable-resolver" ${pkgs.lib.getExe directiveHook} </dev/null 2> hook-error; then
    echo 'directive hook ran a writable program' >&2
    exit 1
  fi
  grep -F 'must resolve inside the Nix store' hook-error
  # Unknown selectors pass through as ordinary vendor arguments.
  for executable in ${wrapper "cc-native"}/bin/cc-native ${wrapper "cx-native"}/bin/cx-native; do
    "$executable" fixture-unknown 'two words'
    grep -Fx 'fixture-unknown' "$AGENT_TEST_ARGS"
    grep -Fx 'two words' "$AGENT_TEST_ARGS"
  done
  ${wrapper "cc-native"}/bin/cc-native
  python3 - <<'PYTEST'
  import json, pathlib
  args = pathlib.Path('args').read_text().splitlines()
  config = json.loads(pathlib.Path(args[args.index('--mcp-config') + 1]).read_text())
  assert config == {'mcpServers': {}}
  PYTEST
  ${wrapper "cx-native"}/bin/cx-native
  if grep -F 'mcp_servers.' "$AGENT_TEST_ARGS"; then
    echo 'wrapper injected an MCP server' >&2
    exit 1
  fi
  # Discovery is delivered through each vendor's real prompt argument.
  git init --quiet memory-project
  printf 'A reproducible packaging constraint.\n' > memory-draft.md
  ${pkgs.lib.getExe (agents.memory pkgs)} --project-root "$PWD/memory-project" \
    add project:integration \
    --trigger 'When packaging the fixture' --file memory-draft.md
  for executable in ${wrapper "cc-native"}/bin/cc-native ${wrapper "cx-native"}/bin/cx-native; do
    (cd memory-project && "$executable")
    python3 - <<'PY'
  from pathlib import Path
  args = Path('args').read_text()
  assert 'project:integration' in args
  assert 'When packaging the fixture' in args
  PY
  done
  touch "$out"
''
