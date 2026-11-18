# Refresh the plugin source only, not the host or Caddy executable.
if [ "$#" -ne 0 ]; then
  printf 'Usage: nup-refresh-caddy\n' >&2
  exit 2
fi

target='.#nixosConfigurations.lanser.config.services.caddy.package.src'
hash_file='data/serve/caddy/source.json'
hash=$(jq -er '.hash | strings' "$hash_file")
drv=$(nix eval --raw "$target.drvPath")
temporary=$(mktemp -d)
restore=0
cleanup() {
  if [ "$restore" -eq 1 ]; then
    cp -- "$temporary/original" "$hash_file"
    printf 'Restored the previous Caddy hash. The updated flake.lock is retained\n' >&2
  fi
  rm -rf -- "$temporary"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if nix build --no-link "$target" 2> "$temporary/stderr"; then
  cat "$temporary/stderr" >&2
  exit 0
fi
cat "$temporary/stderr" >&2

# Accept exactly one mismatch for this derivation and its existing hash.
diagnostic=$(cat "$temporary/stderr")
pattern="error: hash mismatch in fixed-output derivation '([^']+)':[[:space:]]+specified:[[:space:]]+([^[:space:]]+)[[:space:]]+got:[[:space:]]+(sha256-[A-Za-z0-9+/]{43}=)"
count=0
replacement=''
while [[ "$diagnostic" =~ $pattern ]]; do
  matched=${BASH_REMATCH[0]}
  if [ "${BASH_REMATCH[1]}" = "$drv" ] && [ "${BASH_REMATCH[2]}" = "$hash" ]; then
    replacement=${BASH_REMATCH[3]}
    count=$((count + 1))
  fi
  diagnostic=${diagnostic#*"$matched"}
done
if [ "$count" -ne 1 ] || [ "$replacement" = "$hash" ]; then
  printf 'Caddy source build failed without a unique new matching hash; hash left unchanged\n' >&2
  exit 1
fi

cp -- "$hash_file" "$temporary/original"
jq --arg hash "$replacement" '.hash = $hash' "$hash_file" > "$temporary/updated"
restore=1
cat "$temporary/updated" > "$hash_file"
printf 'Updated Caddy plugin source hash to %s; verifying...\n' "$replacement"
nix build --no-link "$target"
restore=0
