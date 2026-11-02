{ inputs, pkgs, ... }:
let
  # No real keys or keyrings: exercise the operational checks' exit status
  # with deterministic stand-ins for the public-key derivation tools.
  context = {
    pathv-pgp-private = "private";
    pathv-pgp-public = "public";
    pathv-emerg-age-private = "private";
    pathv-emerg-age-public = "public";
    pathv-emerg-ssh-private = "private";
    pathv-emerg-ssh-public = "public";
    bash-get-keyid = "keyid=fixture";
    env.keyid = "keyid";
  };
  scripts = map (path: pkgs.writeText "key-verification.sh"
    (import (inputs.self.data.path "cryptid/scripts/operations/${path}") { inherit context; }).content
  ) [ "age/age-emerg-test.nix" "ssh/ssh-emerg-test.nix" "gpg/gpg-test.nix" ];
in
pkgs.runCommand "cryptid-key-verification-test" { } ''
  export GNUPGHOME="$TMPDIR/keyring"
  export FIXTURE_PUBLIC="$TMPDIR/public"
  echo fixture-public > "$FIXTURE_PUBLIC"
  timestamped_last() { echo "$FIXTURE_PUBLIC"; }
  derived_public() {
    if [[ "$KEY_MATCH" == 1 ]]; then echo fixture-public; else echo wrong-public; fi
  }
  age-keygen() { derived_public; }
  ssh-keygen() { derived_public; }
  gpg() {
    if [[ "$1" == --export ]]; then derived_public; fi
    return 0
  }
  export -f timestamped_last derived_public age-keygen ssh-keygen gpg
  for script in ${pkgs.lib.escapeShellArgs scripts}; do
    KEY_MATCH=1 bash -e "$script" > matched.log 2>&1
    if KEY_MATCH=0 bash -e "$script" > mismatched.log 2>&1; then
      echo 'key verification reported success for a mismatched public key' >&2
      cat mismatched.log >&2
      exit 1
    fi
    grep -F 'CORRUPT OR INVALID' mismatched.log
  done
  touch "$out"
''
