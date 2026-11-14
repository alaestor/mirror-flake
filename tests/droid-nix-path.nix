# Removal check, not just a regression test: upstream lookup succeeding is
# good news and deliberately fails the build to prompt cleanup. See
# docs/hosts-and-homes.md, "NIX_PATH workaround removal check", for the
# distinction between that signal and a broken configured environment.
{ inputs, pkgs, system }:
let
  androidPkgs = import inputs.android-nixpkgs {
    system = "aarch64-linux";
    overlays = [ inputs.nix-on-droid.overlays.default ];
  };
  evaluate = modules: inputs.nix-on-droid.lib.nixOnDroidConfiguration {
    pkgs = androidPkgs;
    bootstrapSystem = system;
    modules = [
      {
        system.stateVersion = "24.05";
        user.uid = 10000;
        user.gid = 10000;
      }
    ] ++ modules;
  };
  upstream = evaluate [ ];
  configured = evaluate [ inputs.self.modules.nixOnDroid.global-config ];

  # Execute the generated session setup, remapping only the Android home
  # into a private fixture. Its package references need not be built: the
  # session script exports their paths but this test runs native Nix.
  session = name: evaluated: pkgs.writeText "${name}-session.sh" (
    builtins.replaceStrings
      [ evaluated.config.user.home ]
      [ "\${NIX_PATH_TEST_HOME}" ]
      (builtins.unsafeDiscardStringContext evaluated.config.build.sessionInit.text)
  );
  nixConfig = name: evaluated: pkgs.writeText "${name}-nix.conf"
    (builtins.unsafeDiscardStringContext evaluated.config.environment.etc."nix/nix.conf".text);
  registry = name: evaluated: pkgs.writeText "${name}-registry.json"
    evaluated.config.environment.etc."nix/registry.json".text;
in
pkgs.runCommand "droid-nix-path-test" {
  nativeBuildInputs = [ pkgs.nix ];
  expectedNixpkgs = androidPkgs.path;
} ''
  for scenario in upstream configured; do
    export scenario
    export NIX_PATH_TEST_HOME="$TMPDIR/$scenario/home"
    export NIX_CONF_DIR="$TMPDIR/$scenario/conf"
    export XDG_CONFIG_HOME="$TMPDIR/$scenario/config"
    export NIX_USER_CONF_FILES=/dev/null
    mkdir -p "$NIX_PATH_TEST_HOME/.nix-profile/etc/profile.d" "$NIX_CONF_DIR"
    # Bootstrap normally supplies nix.sh. Start without inherited channels
    # or search paths so they cannot conceal the flake-only setup's bug.
    touch "$NIX_PATH_TEST_HOME/.nix-profile/etc/profile.d/nix.sh"
    case "$scenario" in
      upstream)
        export sessionScript=${session "upstream" upstream}
        cp ${nixConfig "upstream" upstream} "$NIX_CONF_DIR/nix.conf"
        export registryFile=${registry "upstream" upstream}
        ;;
      configured)
        export sessionScript=${session "configured" configured}
        cp ${nixConfig "configured" configured} "$NIX_CONF_DIR/nix.conf"
        export registryFile=${registry "configured" configured}
        ;;
    esac
    ${pkgs.bash}/bin/bash --noprofile --norc -e <<'SH'
      unset NIX_PATH __NOD_SESS_INIT_SOURCED
      source "$sessionScript"
      if nix-instantiate --option flake-registry "$registryFile" --find-file nixpkgs > resolved 2> lookup-error; then
        if [ "$scenario" = upstream ]; then
          cat >&2 <<'MESSAGE'
  GOOD NEWS: nix-on-droid resolves <nixpkgs> without our workaround in this fixture.
  This intentional check failure is a cleanup reminder, not a runtime regression.
  Verify the resolved source and confirm lookup on-device without the workaround.
  Once confirmed, remove nix.nixPath from modules/host-plumbing/global-config.nix
  and retire tests/droid-nix-path.nix. Do not preserve an obsolete workaround
  just to make this check pass. See docs/hosts-and-homes.md, under
  "NIX_PATH workaround removal check". Resolved source:
  MESSAGE
          cat resolved >&2
          exit 1
        fi
        if [ "$(cat resolved)" != "$expectedNixpkgs" ]; then
          echo "The nix-on-droid workaround resolved a different nixpkgs source; expected $expectedNixpkgs." >&2
          cat resolved >&2
          exit 1
        fi
      else
        if [ "$scenario" = configured ]; then
          echo "The nix-on-droid NIX_PATH workaround no longer resolves nixpkgs." >&2
          cat lookup-error >&2
          exit 1
        fi
        grep -F "file 'nixpkgs' was not found" lookup-error
      fi
  SH
  done
  touch "$out"
''
