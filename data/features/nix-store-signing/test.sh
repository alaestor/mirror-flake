#!/usr/bin/env bash

set -euo pipefail

provisioner=$1
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

age-keygen --output "$fixture/identity" >/dev/null 2>&1
recipient=$(age-keygen -y "$fixture/identity")

mkdir "$fixture/bin"
printf '#!%s\n' "$(command -v bash)" > "$fixture/bin/nix-store"
cat >> "$fixture/bin/nix-store" <<'EOF'
set -euo pipefail
test "$1" = --generate-binary-cache-key
printf '%s\n' "$2:TEST-SECRET" > "$3"
if [[ ${SIGNING_TEST_FAIL_GENERATION:-0} == 1 ]]; then
  exit 1
fi
printf '%s\n' "$2:TEST-PUBLIC" > "$4"
EOF
chmod +x "$fixture/bin/nix-store"
export PATH="$fixture/bin:$PATH"
mkdir "$fixture/temporary-keys"
export TMPDIR="$fixture/temporary-keys"

assert_no_temporary_keys() {
  shopt -s nullglob dotglob
  local remaining=("$TMPDIR"/*)
  test "${#remaining[@]}" -eq 0
}

mkdir "$fixture/success"
cd "$fixture/success"
bash "$provisioner" \
  --key-name test.example-1 \
  --recipient "$recipient"

test -f test.example-1.nsk.age
test -f test.example-1.nsk.pub
test ! -e test.example-1
test "$(stat -c %a test.example-1.nsk.age)" = 600
test "$(stat -c %a test.example-1.nsk.pub)" = 644

age --decrypt --identity "$fixture/identity" test.example-1.nsk.age > "$fixture/secret"
grep -q '^test\.example-1:TEST-SECRET$' "$fixture/secret"
grep -q '^test\.example-1:TEST-PUBLIC$' test.example-1.nsk.pub
assert_no_temporary_keys

cp test.example-1.nsk.age "$fixture/original-secret"
cp test.example-1.nsk.pub "$fixture/original-public"
if bash "$provisioner" --key-name test.example-1 --recipient "$recipient"; then
  echo "ERROR: provisioning unexpectedly overwrote existing outputs" >&2
  exit 1
fi
cmp test.example-1.nsk.age "$fixture/original-secret"
cmp test.example-1.nsk.pub "$fixture/original-public"

if bash "$provisioner" --key-name ../escape --recipient "$recipient"; then
  echo "ERROR: provisioning accepted an unsafe key name" >&2
  exit 1
fi

# Neither a partially generated key nor an encryption failure may leave a
# plaintext secret, published output, or staging file behind.
mkdir "$fixture/failures"
cd "$fixture/failures"
if SIGNING_TEST_FAIL_GENERATION=1 bash "$provisioner" --key-name failed --recipient "$recipient"; then
  echo 'ERROR: partial key generation unexpectedly succeeded' >&2
  exit 1
fi
assert_no_temporary_keys
if bash "$provisioner" --key-name failed --recipient invalid-recipient; then
  echo 'ERROR: encryption unexpectedly succeeded with an invalid recipient' >&2
  exit 1
fi
assert_no_temporary_keys
remaining=("$PWD"/*)
test "${#remaining[@]}" -eq 0

# A dangling symlink counts as an existing output, too.
ln -s "$fixture/missing-target" failed.nsk.age
if bash "$provisioner" --key-name failed --recipient "$recipient"; then
  echo 'ERROR: provisioning overwrote a dangling output symlink' >&2
  exit 1
fi
test -L failed.nsk.age
test ! -e "$fixture/missing-target"
test ! -e failed.nsk.pub
