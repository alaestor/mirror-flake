## lib

Creates a script which writes a NixOS ISO to a block device. `postWrite`
can add host-specific operations after the ISO has been written.

Creates a nixos-anywhere deployer for a host using the `ssh-host` and
`standard-disk` modules.

## mkflakedocs

Destructively regenerates `README.md` files recursively by extracting `/**` doc-strings from nix files. By default, it only recurses subfolders and doesn't generate a top-level `./README.md` unless the `--include-root` argument is used.

E.g. in flake root:
```
nix run mkflakedocs
```
