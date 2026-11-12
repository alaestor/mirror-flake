{ inputs, pkgs, system }:
let
  lib = pkgs.lib;
  # Generate test-only administrative identities at build time. The shim only
  # substitutes their recipients; encryption and decryption use real age.
  ageShim = pkgs.writeShellApplication {
    name = "age";
    text = ''
      args=()
      for arg in "$@"; do
        case "$arg" in
          fixture-primary) arg="$TEST_PRIMARY_RECIPIENT" ;;
          fixture-recovery) arg="$TEST_RECOVERY_RECIPIENT" ;;
        esac
        args+=("$arg")
      done
      exec ${pkgs.age}/bin/age "''${args[@]}"
    '';
  };
  sshMock = pkgs.writeShellScript "deployment-ssh-mock" ''
    if [ "''${!#}" != true ]; then cat >/dev/null; fi
    touch "$TEST_CAPTURE/ssh-called"
  '';
  sshShim = pkgs.runCommand "deployment-openssh" { } ''
    mkdir -p "$out/bin"
    ln -s ${sshMock} "$out/bin/ssh"
    ln -s ${pkgs.openssh}/bin/ssh-keygen "$out/bin/ssh-keygen"
  '';
  anywhereMock = pkgs.writeShellApplication {
    name = "nixos-anywhere";
    runtimeInputs = [ pkgs.coreutils pkgs.openssh ];
    text = ''
      staging="" password="" identity=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --extra-files) staging=$2; shift 2 ;;
          --disk-encryption-keys) password=$3; shift 3 ;;
          -i) identity=$2; shift 2 ;;
          *) shift ;;
        esac
      done
      test -n "$staging" && test -n "$password" && test -n "$identity"
      printf '%s\n' "$staging" "$(dirname "$identity")" > "$TEST_CAPTURE/temp-dirs"
      test "$(stat -c %a "$staging")" = 700
      test "$(cat "$password")" = fixture-passphrase
      test "$(stat -c %a "$password")" = 600
      test ! -e "$staging/luks-setup-password"
      case "$password" in "$staging"/*) exit 1 ;; esac
      test -f "$identity"
      test "$(stat -c %a "$staging/etc/ssh/fixture-stable")" = 600
      ssh-keygen -y -P "" -f "$staging/etc/ssh/fixture-stable" | cut -d ' ' -f1,2 > "$TEST_CAPTURE/system.pub"
      cmp "$staging/etc/ssh/fixture-stable.pub" "$TEST_CAPTURE/system.pub"
      if [ "$TEST_EXPECT_INITRD" = 1 ]; then
        test "$(stat -c %a "$staging/etc/secrets/initrd/fixture")" = 600
        ssh-keygen -y -P "" -f "$staging/etc/secrets/initrd/fixture" | cut -d ' ' -f1,2 > "$TEST_CAPTURE/initrd.pub"
        if cmp -s "$TEST_CAPTURE/system.pub" "$TEST_CAPTURE/initrd.pub"; then
          echo "system and initrd identities must differ" >&2
          exit 1
        fi
      else
        test ! -e "$staging/etc/secrets/initrd/fixture"
      fi
      if [ "''${TEST_DEPLOY_SIGNAL:-0}" = 1 ]; then
        kill -TERM "$PPID"
        exit 0
      fi
      exit "''${TEST_DEPLOY_STATUS:-0}"
    '';
  };
  deployer = initrd: (
    import "${inputs.self}/modules/utils/lib.nix" {
      inherit inputs lib;
      self = inputs.self // {
        data = inputs.self.data // {
          vars = inputs.self.data.vars // {
            administrativeAgeRecipients = [ "fixture-primary" "fixture-recovery" ];
          };
        };
      };
    }
  ).config.flake.lib.mkNixosAnywhereDeployer {
    name = "fixture";
    pkgs = pkgs // {
      age = ageShim;
      openssh = sshShim;
      nixos-anywhere = anywhereMock;
    };
    system-config = {
      ssh-host = {
        hostKeyPath = "/etc/ssh/fixture-stable";
        initrd = {
          enable = initrd;
          hostKeyPath = "/etc/secrets/initrd/fixture";
        };
      };
      standard-disk.luks-setup-password-file = "/run/keys/luks-password";
    };
  };
in
pkgs.runCommand "nixos-anywhere-deployer-test" {
  nativeBuildInputs = [ pkgs.age pkgs.openssh pkgs.coreutils pkgs.findutils ];
} ''
  umask 077
  export TEST_CAPTURE="$TMPDIR/capture"
  mkdir "$TEST_CAPTURE" "$TMPDIR/workspace" "$TMPDIR/deployer-tmp"
  export TMPDIR="$TMPDIR/deployer-tmp"
  age-keygen -o "$TEST_CAPTURE/primary" 2>/dev/null
  age-keygen -o "$TEST_CAPTURE/recovery" 2>/dev/null
  TEST_PRIMARY_RECIPIENT=$(age-keygen -y "$TEST_CAPTURE/primary")
  TEST_RECOVERY_RECIPIENT=$(age-keygen -y "$TEST_CAPTURE/recovery")
  export TEST_PRIMARY_RECIPIENT TEST_RECOVERY_RECIPIENT
  cd "$TEST_CAPTURE/../workspace"
  touch flake.nix
  mkdir -p secrets/ssh-host data/identities/ssh-host
  cp "$TEST_CAPTURE/primary" secrets/age_sk.txt
  backup=secrets/ssh-host/ssh_host_ed25519_key_fixture.age
  public=data/identities/ssh-host/ssh_host_ed25519_key_fixture.pub

  run_deploy() {
    printf 'fixture-passphrase\nfixture-passphrase\n' | "$1" root@installer.invalid > "$TEST_CAPTURE/log" 2>&1 || {
      cat "$TEST_CAPTURE/log" >&2
      return 1
    }
  }
  check_cleanup() {
    test -z "$(find "$TMPDIR" -mindepth 1 -print -quit)"
    test -z "$(find secrets/ssh-host data/identities/ssh-host -name '.*.??????' -print -quit)"
    if [ -f "$TEST_CAPTURE/temp-dirs" ]; then
      while IFS= read -r path; do test ! -e "$path"; done < "$TEST_CAPTURE/temp-dirs"
    fi
  }
  expect_failure() {
    rm -f "$TEST_CAPTURE/ssh-called" "$TEST_CAPTURE/temp-dirs"
    if run_deploy "''${2:-${deployer false}/bin/deploy-fixture}"; then
      echo "unexpected deployment success" >&2
      exit 1
    fi
    grep -F "$1" "$TEST_CAPTURE/log"
    test ! -e "$TEST_CAPTURE/ssh-called"
    check_cleanup
  }

  export TEST_EXPECT_INITRD=0
  # Encryption failure must leave no published identity or temporary files.
  primary_recipient=$TEST_PRIMARY_RECIPIENT
  export TEST_PRIMARY_RECIPIENT=invalid-recipient
  expect_failure "unknown recipient type"
  test ! -e "$backup" && test ! -e "$public"
  export TEST_PRIMARY_RECIPIENT=$primary_recipient

  # First installation creates a backup decryptable by both administrators.
  run_deploy ${deployer false}/bin/deploy-fixture
  check_cleanup
  age -d -i "$TEST_CAPTURE/primary" "$backup" > "$TEST_CAPTURE/restored"
  ssh-keygen -y -P "" -f "$TEST_CAPTURE/restored" | cut -d ' ' -f1,2 > "$TEST_CAPTURE/restored.pub"
  cmp "$TEST_CAPTURE/restored.pub" "$TEST_CAPTURE/system.pub"
  age -d -i "$TEST_CAPTURE/recovery" "$backup" > "$TEST_CAPTURE/recovery-restored"
  cmp "$TEST_CAPTURE/restored" "$TEST_CAPTURE/recovery-restored"
  cp "$backup" "$TEST_CAPTURE/original.age"
  cp "$public" "$TEST_CAPTURE/original.pub"

  # Reinstallation restores the same identity, accepting different comments.
  sed -i 's/ fixture$/ changed-comment/' "$public"
  run_deploy ${deployer false}/bin/deploy-fixture
  cmp "$backup" "$TEST_CAPTURE/original.age"
  cmp "$TEST_CAPTURE/restored.pub" "$TEST_CAPTURE/system.pub"
  check_cleanup

  # Missing counterparts, wrong identities, mismatches and corrupt backups
  # fail before any SSH connection, not just before the destructive command.
  rm "$backup"
  expect_failure "Refusing to generate a replacement identity"
  cp "$TEST_CAPTURE/original.age" "$backup"
  rm "$public"
  expect_failure "without a readable public identity"
  cp "$TEST_CAPTURE/original.pub" "$public"
  rm secrets/age_sk.txt
  expect_failure "identity is unreadable"
  # An unrelated identity must not decrypt either administrative recipient.
  age-keygen -o "$TEST_CAPTURE/unrelated" 2>/dev/null
  cp "$TEST_CAPTURE/unrelated" secrets/age_sk.txt
  expect_failure "no identity matched"
  cp "$TEST_CAPTURE/primary" secrets/age_sk.txt
  ssh-keygen -q -t ed25519 -N "" -f "$TEST_CAPTURE/other-host"
  cp "$TEST_CAPTURE/other-host.pub" "$public"
  expect_failure "private key does not match"
  cp "$TEST_CAPTURE/original.pub" "$public"
  printf 'corrupt\n' > "$backup"
  expect_failure "failed to read header"
  cp "$TEST_CAPTURE/original.age" "$backup"

  mkdir -p secrets/hosts/fixture
  touch secrets/hosts/fixture/initrd-hostkey.pub
  expect_failure "legacy initrd host-key files" ${deployer true}/bin/deploy-fixture
  rm secrets/hosts/fixture/initrd-hostkey.pub

  # Both roles are staged separately; failures in nixos-anywhere still clean
  # all local plaintext and preserve the recoverable encrypted backups.
  export TEST_EXPECT_INITRD=1
  run_deploy ${deployer true}/bin/deploy-fixture
  check_cleanup
  run_deploy ${deployer true}/bin/deploy-fixture
  check_cleanup
  export TEST_DEPLOY_STATUS=23
  if run_deploy ${deployer true}/bin/deploy-fixture; then exit 1; fi
  check_cleanup
  unset TEST_DEPLOY_STATUS
  export TEST_DEPLOY_SIGNAL=1
  if run_deploy ${deployer true}/bin/deploy-fixture; then exit 1; fi
  check_cleanup
  test -f "$backup"
  touch "$out"
''
