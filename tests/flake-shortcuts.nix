{ inputs, pkgs, ... }:
let
  shortcuts = isNixOnDroid: (import (inputs.self.data.path "features/standard-terminal/scripts/flake-shortcuts.nix") {
    inherit pkgs isNixOnDroid;
  }).package;
in
pkgs.runCommand "flake-shortcuts-test" { } ''
  mkdir -p "$TMPDIR/stubs"
  cat > "$TMPDIR/stubs/home-manager" <<'SH'
  #!${pkgs.runtimeShell}
  printf '%s\n' "$@" > "$HOME_MANAGER_CALL"
  exit 0
  SH
  chmod +x "$TMPDIR/stubs/home-manager"
  export PATH="$TMPDIR/stubs:$PATH"
  export HOME_MANAGER_CALL="$TMPDIR/home-manager-call"

  for shortcuts in ${shortcuts false} ${shortcuts true}; do
    export XDG_STATE_HOME="$TMPDIR/$(basename "$shortcuts")"
    cache="$XDG_STATE_HOME/nix-flake-shortcuts/target"

    if "$shortcuts/bin/nwhere" > actual 2> error; then
      echo 'nwhere must fail when no target is cached' >&2
      exit 1
    fi
    test ! -s actual
    grep -F 'no flake target is cached' error
    test ! -e "$cache"

    target='github:example/dotfiles#test-host'
    "$shortcuts/bin/hswitch" --flake "$target"
    cp "$cache" expected
    "$shortcuts/bin/nwhere" > actual
    cmp expected actual
    cmp expected "$cache"

    "$shortcuts/bin/hbuild"
    printf '%s\n' build --flake "$target" > expected-call
    cmp expected-call "$HOME_MANAGER_CALL"
    cmp expected "$cache"

    "$shortcuts/bin/hbuild" --flake 'github:example/other#user'
    printf '%s\n' build --flake 'github:example/other#user' > expected-call
    cmp expected-call "$HOME_MANAGER_CALL"
    "$shortcuts/bin/hswitch" --flake "$target"

    mkdir -p "$TMPDIR/flake with spaces"
    target="path:$TMPDIR/flake with spaces#test-host"
    "$shortcuts/bin/hswitch" --flake "$target"
    printf '%s\n' "$target" > expected
    "$shortcuts/bin/nwhere" > actual
    cmp expected actual
    cmp expected "$cache"

    if "$shortcuts/bin/nwhere" unexpected > actual 2> error; then
      echo 'nwhere must reject arguments' >&2
      exit 1
    fi
    test ! -s actual
    grep -F 'Usage:' error
    cmp expected "$cache"

    printf '\n' > "$cache"
    if "$shortcuts/bin/nwhere" > actual 2> error; then
      echo 'nwhere must fail when the cached target is empty' >&2
      exit 1
    fi
    test ! -s actual
    grep -F 'cached flake target is empty' error
  done
  touch "$out"
''
