#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/project/nucleus" "$work/bin"
cp "$source_dir/bootstrap.sh" "$work/project/nucleus/bootstrap.sh"
cp "$source_dir/bootstrap-flake.nix" "$work/project/nucleus/bootstrap-flake.nix"

# Exercise the bootstrap's file handling without resolving real flake inputs.
printf '#!%s\n' "$BASH" > "$work/bin/nix"
cat >> "$work/bin/nix" <<'EOF'
set -euo pipefail
case "$*" in
  'run --no-write-lock-file .#write-flake -- --no-check')
    cmp nucleus/bootstrap-flake.nix flake.nix
    printf '%s\n' generated > flake.nix
    ;;
  'flake lock') touch flake.lock ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$work/bin/nix"
export PATH="$work/bin:$PATH"
cd "$work/project"

# A new project needs no existing flake and produces no spurious backup.
bash nucleus/bootstrap.sh
test "$(cat flake.nix)" = generated
test -f flake.lock
shopt -s nullglob
backups=(flake.nix.pre-bootstrap.*)
test "${#backups[@]}" -eq 0

# Recovery preserves the old source before replacing it.
printf '%s\n' broken > flake.nix
bash nucleus/bootstrap.sh
backups=(flake.nix.pre-bootstrap.*)
test "${#backups[@]}" -eq 1
test "$(cat "${backups[0]}")" = broken
test "$(cat flake.nix)" = generated

# Reusing the seed itself must not create another backup.
cp nucleus/bootstrap-flake.nix flake.nix
bash nucleus/bootstrap.sh
backups=(flake.nix.pre-bootstrap.*)
test "${#backups[@]}" -eq 1

# Reject unrelated working directories without writing a flake.
cd "$work"
if bash "$source_dir/bootstrap.sh" > rejected.log 2>&1; then
  echo 'bootstrap accepted an unrelated directory' >&2
  exit 1
fi
test ! -e flake.nix
