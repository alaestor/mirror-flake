{ inputs, pkgs, ... }:
pkgs.runCommand "nup-tests" {
  nativeBuildInputs = [ pkgs.nushell pkgs.python3 ];
  FLAKE_HELPERS = inputs.self.data.path "programs/nushell/flake-helpers.nu";
} ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  python3 ${inputs.self}/tests/nup/test_nup.py
  touch "$out"
''
