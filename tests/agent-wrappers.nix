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
  events = [
    "PostToolUse"
    "Stop"
    "SessionStart"
    "PreCompact"
  ];
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
assert !(builtins.hasAttr ".serena-cxs/serena_config.yml" cfg.home.file);
pkgs.runCommand "agent-wrappers-test" { } ''
  for wrapper in ${
    pkgs.lib.escapeShellArgs (map (package: "${package}/bin/${package.name}") wrappers)
  }; do
    if grep -qi serena "$wrapper"; then
      echo "unexpected Serena dependency in $wrapper" >&2
      exit 1
    fi
  done
  ${pkgs.lib.concatMapStringsSep "\n" (package: ''
    ${package}/bin/${package.name} --${
      if pkgs.lib.hasPrefix "cc" package.name then "cc" else "cx"
    }-help > /dev/null
  '') wrappers}
  touch "$out"
''
