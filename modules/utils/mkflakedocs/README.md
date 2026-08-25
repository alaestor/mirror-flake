## mkflakedocs

Destructively regenerates `README.md` files recursively by extracting `/**` doc-strings from nix files. By default, it only recurses subfolders and doesn't generate a top-level `./README.md` unless the `--include-root` argument is used.

E.g. in flake root:
```
nix run mkflakedocs
```
