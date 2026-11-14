{ inputs, pkgs, ... }:
let
  script = inputs.self.data.path "features/standard-terminal/ngc.py";
  package = isNixOnDroid: (import (inputs.self.data.path "features/standard-terminal/scripts/ngc.nix") {
    inherit pkgs isNixOnDroid;
  }).package;
in
pkgs.runCommand "ngc-test" {
  nativeBuildInputs = [ pkgs.python3 pkgs.nix ];
  NGC_SOURCE = script;
} ''
  python3 ${inputs.self}/tests/lib/ngc.py
  ${package false}/bin/ngc --help > /dev/null
  ${package true}/bin/ngc --help > /dev/null

  # Verify Nix's deletion primitive against real profile symlinks, without GC.
  export NIX_STATE_DIR="$TMPDIR/nix-state"
  export NIX_STORE_DIR="$TMPDIR/nix-store"
  export NIX_REMOTE=local
  mkdir -p "$TMPDIR/profiles"
  profile="$TMPDIR/profiles/example"
  ln -s ${pkgs.emptyDirectory} "$profile-1-link"
  ln -s ${pkgs.emptyDirectory} "$profile-2-link"
  ln -s example-1-link "$profile"
  nix-env --profile "$profile" --delete-generations 2
  test ! -L "$profile-2-link"
  if nix-env --profile "$profile" --delete-generations 1; then
    echo 'nix-env must refuse to delete the selected generation' >&2
    exit 1
  fi
  test -L "$profile-1-link"
  touch "$out"
''
