#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f flake.nix || ! -f nucleus/bootstrap-flake.nix ]]; then
  printf '%s\n' 'bootstrap must run from the repository root.' >&2
  exit 2
fi

if ! cmp -s nucleus/bootstrap-flake.nix flake.nix; then
  cp flake.nix "flake.nix.pre-bootstrap.$(date +%s)"
fi

cp nucleus/bootstrap-flake.nix flake.nix
chmod u+w flake.nix
nix run --no-write-lock-file .#write-flake -- --no-check
nix flake lock
