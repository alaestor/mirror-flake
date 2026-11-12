## list-modules

Recursively lists `*.nix` files under a directory, skipping `_`-prefixed
entries. Deliberately plain-`builtins`-only (no `lib.hasSuffix`): this is
imported directly from `flake.nix` before flake-parts/nixpkgs inputs are
available to reach `lib` from.
