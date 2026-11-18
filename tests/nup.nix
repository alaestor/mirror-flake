{ inputs, pkgs, ... }:
pkgs.runCommand "nup-tests" {
  nativeBuildInputs = [ pkgs.python3 ];
  FLAKE_SHORTCUTS = (import (inputs.self.data.path "features/standard-terminal/scripts/flake-shortcuts.nix") {
    inherit pkgs;
    isNixOnDroid = false;
  }).package;
} ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  python3 ${inputs.self}/tests/nup/test_nup.py
  touch "$out"
''
