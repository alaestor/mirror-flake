## lib

#### Helper functions for creating system / home-manager configurations
- mkNixos system name nixpkgs;
- mkDarwin system name nixpkgs nix-darwin;
- mkHomeManager system name nixpkgs home-manager;

E.g.
```
flake.nixosConfigurations = inputs.self.lib.mkNixos
"x86_64-linux" "desktop" inputs.unstable-nixpkgs;
```

## mkflakedocs

Destructively regenerates `README.md` files recursively by extracting `/**` doc-strings from nix files. By default, it only recurses subfolders and doesn't generate a top-level `./README.md` unless the `--include-root` argument is used.

E.g. in flake root:
```
nix run mkflakedocs
```
