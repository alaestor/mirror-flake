#!/usr/bin/env bash
if [[ -n "${1:-}" ]]; then
  printf 'pickup takes no arguments\n' >&2
  exit 2
fi

shopt -s nullglob
candidates=(.agents/session/*.md)
if [[ -f .agents/handoff.md ]]; then
  candidates+=(.agents/handoff.md)
fi
if (( ${#candidates[@]} == 0 )); then
  printf 'No handoff exists under .agents/\n' >&2
  exit 1
fi

latest="${candidates[0]}"
for candidate in "${candidates[@]:1}"; do
  if [[ "$candidate" -nt "$latest" ]]; then
    latest="$candidate"
  fi
done
absolute="$(realpath -- "$latest")"
printf 'Loaded handoff:\n%s\n' "$absolute" >&2
cat -- "$latest"
