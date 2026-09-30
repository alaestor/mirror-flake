{ pkgs, ... }:
{
  description = "List available directives";
  displayOnly = true;
  command = pkgs.writeShellApplication {
    name = "agent-directive-list";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      if [[ -n "''${1:-}" ]]; then
        printf 'list takes no arguments\n' >&2
        exit 2
      fi
      jq -r '
        sort_by(.name)[] |
        "- \(.name)" +
        (if .kind == "script" then "   — \(.description)" else "" end)
      ' "$AGENT_DIRECTIVES_CATALOGUE" >&2
    '';
  };
}
