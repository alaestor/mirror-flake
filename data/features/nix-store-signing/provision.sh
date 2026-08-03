#!/usr/bin/env bash

set -euo pipefail

key_name=""
declare -a recipients=()

usage() {
  cat <<'EOF'
Usage: provision-nix-store-signing-key --key-name NAME --recipient RECIPIENT [--recipient RECIPIENT ...]

Generate a Nix binary-cache signing key, encrypt the secret key with age, and
write NAME.nsk.age and NAME.nsk.pub to the current directory. No plaintext secret
key is retained.
EOF
}

while (($#)); do
  case "$1" in
    --key-name)
      [[ $# -ge 2 ]] || { echo "ERROR: --key-name requires a value" >&2; exit 2; }
      key_name=$2
      shift 2
      ;;
    --recipient)
      [[ $# -ge 2 ]] || { echo "ERROR: --recipient requires a value" >&2; exit 2; }
      recipients+=("$2")
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "$key_name" ]] || { echo "ERROR: --key-name is required" >&2; exit 2; }
[[ "$key_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
  echo "ERROR: invalid key name: $key_name" >&2
  exit 2
}
((${#recipients[@]} > 0)) || { echo "ERROR: at least one --recipient is required" >&2; exit 2; }

secret_output="$PWD/$key_name.nsk.age"
public_output="$PWD/$key_name.nsk.pub"

for output in "$secret_output" "$public_output"; do
  if [[ -e "$output" || -L "$output" ]]; then
    echo "ERROR: refusing to overwrite: $output" >&2
    exit 1
  fi
done

umask 077
generation_directory=$(mktemp -d "${TMPDIR:-/tmp}/nix-store-signing.XXXXXXXX")
secret_key="$generation_directory/$key_name"
public_temporary=$(mktemp "$PWD/.$key_name.nsk.pub.tmp.XXXXXXXX")
secret_temporary=$(mktemp "$PWD/.$key_name.nsk.age.tmp.XXXXXXXX")

cleanup() {
  rm -rf "$generation_directory"
  rm -f "$public_temporary" "$secret_temporary"
}
trap cleanup EXIT

nix-store --generate-binary-cache-key "$key_name" "$secret_key" "$public_temporary"

declare -a age_arguments=()
for recipient in "${recipients[@]}"; do
  age_arguments+=(--recipient "$recipient")
done

age "${age_arguments[@]}" --output "$secret_temporary" "$secret_key"
chmod 0600 "$secret_temporary"
chmod 0644 "$public_temporary"

mv "$secret_temporary" "$secret_output"
mv "$public_temporary" "$public_output"

echo "Created $secret_output"
echo "Created $public_output"
echo "Move them into the repository's encrypted-secret and public-identity trees, then declare their consumers."
