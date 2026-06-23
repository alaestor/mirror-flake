set -euo pipefail
rm -rf ./flake.nix
cp flake-file.nix flake.nix
nix run .#write-flake
