/**
  Packages the harness-independent memory CLI. Prompts are separate editable
  Markdown files under data/agents/memory/prompts; see docs/memory.md.
*/
{ self, ... }:
let
  memory =
    pkgs:
    pkgs.stdenvNoCC.mkDerivation {
      pname = "agent-memory";
      version = "1";
      src = self.data.path "agents/memory";
      nativeBuildInputs = [ pkgs.makeWrapper ];
      installPhase = ''
        mkdir -p $out/lib/agent-memory $out/bin
        cp src/memory.py $out/lib/agent-memory/memory.py
        cp settings.json $out/lib/agent-memory/settings.json
        cp -r prompts $out/lib/agent-memory/prompts
        makeWrapper ${pkgs.python3}/bin/python3 $out/bin/memory \
          --add-flags $out/lib/agent-memory/memory.py \
          --set AGENT_MEMORY_PROMPTS $out/lib/agent-memory/prompts \
          --set-default AGENT_MEMORY_CONFIG $out/lib/agent-memory/settings.json \
          --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.git ]}
      '';
      meta.mainProgram = "memory";
    };
in
{
  flake.lib.agents.memory = memory;
  perSystem = { pkgs, ... }: {
    packages.agent-memory = memory pkgs;
  };
}
