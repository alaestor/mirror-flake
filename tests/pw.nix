{ inputs, pkgs, ... }:
let
  makePw = packages: (import (inputs.self.data.path "features/standard-terminal/scripts/pw.nix") {
    pkgs = packages;
  }).package;
  fakeDiceware = pkgs.writeShellScriptBin "diceware" ''
    if [ "''${DICEWARE_FAIL:-0}" = 1 ]; then exit 17; fi
    [ "$#" -eq 5 ] && [ "$1" = -d ] && [ "$2" = _ ] && [ "$3" = -n ] && [ "$5" = --no-caps ] || exit 18
    for ((i = 0; i < $4; i++)); do
      if [ "$i" -gt 0 ]; then printf '_'; fi
      printf 'word'
    done
    printf '\n'
  '';
in
pkgs.runCommand "pw-tests" {
  nativeBuildInputs = [ pkgs.python3 ];
  PW = "${makePw pkgs}/bin/pw";
  PW_STUB = "${makePw (pkgs // { diceware = fakeDiceware; })}/bin/pw";
} ''
  python3 ${inputs.self}/tests/pw/test_pw.py
  touch "$out"
''
