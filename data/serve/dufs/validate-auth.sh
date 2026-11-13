# Dufs otherwise treats missing/empty auth as anonymous access. Permit only
# named accounts with SHA-512 crypt hashes and read-only access to the root.
fail() {
  echo 'Dufs requires DUFS_AUTH with named, hashed, read-only accounts.' >&2
  exit 1
}

[[ -n "${DUFS_AUTH:-}" ]] || fail
[[ "$DUFS_AUTH" != *$'\n'* && "$DUFS_AUTH" != *$'\r'* ]] || fail
[[ "$DUFS_AUTH" != '|'* && "$DUFS_AUTH" != *'|' && "$DUFS_AUTH" != *'||'* ]] || fail
IFS='|' read -r -a rules <<< "$DUFS_AUTH"
# Literal crypt markers, not shell variable references.
# shellcheck disable=SC2016
pattern='^[a-zA-Z0-9][a-zA-Z0-9_-]*:\$6\$(rounds=[0-9]+\$)?[a-zA-Z0-9./]{1,16}\$[a-zA-Z0-9./]{86}@/:ro$'
for rule in "${rules[@]}"; do
  [[ "$rule" =~ $pattern ]] || fail
done
