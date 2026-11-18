{ inputs, pkgs, ... }:
let
  fakeLsblk = pkgs.writeShellScriptBin "lsblk" ''
    [ "$*" = '-d -l -o NAME,SIZE,MODEL,TRAN,RM,RO --json' ] || exit 18
    if [ "''${LSBLK_FAIL:-0}" = 1 ]; then exit 17; fi
    cat "$LSBLK_FIXTURE"
  '';
  fakeUtilLinux = pkgs.runCommand "lsblkrm-test-util-linux" { } ''
    mkdir -p "$out/bin"
    ln -s ${fakeLsblk}/bin/lsblk "$out/bin/lsblk"
    ln -s ${pkgs.util-linux}/bin/column "$out/bin/column"
  '';
  script = packages: (import (inputs.self.data.path "features/standard-terminal/scripts/lsblkrm.nix") {
    pkgs = packages;
  }).package;
in
pkgs.runCommand "lsblkrm-tests" {
  nativeBuildInputs = [ pkgs.python3 pkgs.nushell ];
  NU_SHORTCUTS = inputs.self.data.path "programs/nushell/shortcuts.nu";
  LSBLKRM = "${script (pkgs // { util-linux = fakeUtilLinux; })}/bin/lsblkrm";
  # Build the real package too, including writeShellApplication's syntax checks.
  realPackage = script pkgs;
} ''
  test -x "$realPackage/bin/lsblkrm"
  python3 ${inputs.self}/tests/lsblkrm/test_lsblkrm.py
  touch "$out"
''
