#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
dir="$root/.agents/memory"

usage() {
  echo 'usage: project-memory {list|read|new|edit|delete} [name]' >&2
  exit 2
}

valid_name() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

validate() {
  local file=$1 field value
  taplo lint --no-auto-config --no-schema "$file" >/dev/null 2>&1
  for field in trigger content; do
    value="$(taplo get -o json -f "$file" "$field")" || return 1
    jq -e 'type == "string" and (gsub("[[:space:]]"; "") | length > 0)' <<<"$value" >/dev/null || return 1
  done
}

case "${1:-}" in
  list)
    [[ $# == 1 ]] || usage
    [[ -d "$dir" ]] || exit 0
    count=0
    shopt -s nullglob
    for file in "$dir"/*.toml; do
      name="${file##*/}"
      name="${name%.toml}"
      valid_name "$name" || { echo "invalid memory filename: $file" >&2; exit 1; }
      validate "$file" || { echo "invalid memory: $file" >&2; exit 1; }
      if (( count == 30 )); then
        echo '(more memories omitted; run project-memory list in the project to inspect them)'
        break
      fi
      trigger="$(taplo get -f "$file" trigger)"
      trigger="${trigger//$'\n'/ }"
      printf '%s: %.200s\n' "$name" "$trigger"
      (( count += 1 ))
    done
    ;;
  read|new|edit|delete)
    [[ $# == 2 ]] || usage
    valid_name "$2" || { echo 'name must be lowercase letters, digits, or hyphens' >&2; exit 2; }
    file="$dir/$2.toml"
    case "$1" in
      read)
        [[ -f "$file" ]] || { echo "memory not found: $2" >&2; exit 1; }
        validate "$file" || { echo "invalid memory: $file" >&2; exit 1; }
        taplo get -s -f "$file" content
        ;;
      new)
        [[ ! -e "$file" ]] || { echo "memory already exists: $2" >&2; exit 1; }
        mkdir -p "$dir"
        tmp="$(mktemp "$dir/.project-memory.XXXXXXXX")"
        printf "trigger = \"\"\n\ncontent = '''\n# %s\n\n'''\n" "$2" >"$tmp"
        "${EDITOR:-vi}" "$tmp"
        validate "$tmp" || { echo "invalid memory; draft retained at $tmp" >&2; exit 1; }
        mv -n -- "$tmp" "$file"
        ;;
      edit)
        [[ -f "$file" ]] || { echo "memory not found: $2" >&2; exit 1; }
        validate "$file" || { echo "invalid memory: $file" >&2; exit 1; }
        tmp="$(mktemp "$dir/.project-memory.XXXXXXXX")"
        cp -- "$file" "$tmp"
        "${EDITOR:-vi}" "$tmp"
        validate "$tmp" || { echo "invalid memory; original unchanged, draft retained at $tmp" >&2; exit 1; }
        mv -- "$tmp" "$file"
        ;;
      delete)
        [[ -f "$file" ]] || { echo "memory not found: $2" >&2; exit 1; }
        rm -- "$file"
        ;;
    esac
    ;;
  *) usage ;;
esac
