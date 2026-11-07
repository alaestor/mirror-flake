{ inputs, pkgs, ... }:
pkgs.runCommand "agent-memory-test"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    MEMORY_SOURCE = inputs.self.data.path "agents/memory/src/memory.py";
    MEMORY_CLI = "${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.agent-memory}/bin/memory";
  }
  ''
    export PYTHONDONTWRITEBYTECODE=1
    python3 ${inputs.self.data.path "agents/memory/tests/test_memory.py"}
    touch $out
  ''
