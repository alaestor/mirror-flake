{ inputs, pkgs, ... }:
let
  record = pkgs.writeTextFile {
    name = "agent-vm-record-command";
    executable = true;
    text = "#!${pkgs.python3}/bin/python3\n" + builtins.readFile ./agent-vm/record-command.py;
  };
  commands = pkgs.runCommand "agent-vm-record-commands" { } ''
    mkdir -p "$out/bin"
    for name in systemctl systemd-run ssh ssh-keyscan; do ln -s ${record} "$out/bin/$name"; done
  '';
  lifecycle = inputs.self.lib.agents.mkVmLifecycle (pkgs // {
    systemd = commands;
    openssh = commands;
  }) {
    name = "fixture";
    hostUser = "fixture";
    sshHostPort = 33333;
    knownHosts = pkgs.writeText "fixture-known-hosts" "fixture";
    lingerSeconds = 2;
    readyTimeoutSeconds = 2;
  };
in
pkgs.runCommand "agent-vm-scripts-test" { nativeBuildInputs = [ pkgs.python3 pkgs.shellcheck ]; } ''
  shellcheck ${inputs.self.data.path "agents/vm/lifecycle.sh"}
  python3 ${./agent-vm/script-test.py} \
    ${pkgs.lib.getExe lifecycle.session} ${pkgs.lib.getExe lifecycle.stop} \
    ${pkgs.lib.getExe lifecycle.restart} ${pkgs.bash}/bin/bash
  touch "$out"
''
