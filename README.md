# Alaestor's flake

A personal [Nix](https://nixos.org/) flake for my configurations.

See [`AGENTS.md`](AGENTS.md) for the contributor model and repository map,
and [`docs/`](docs/) for architecture, secrets handling, and per-subsystem
documentation.

### About Files

#### ./flake.nix

`flake.nix` is generated from distributed `nucleus` declarations and the
modules discovered beneath `modules/`. Regenerate it with:

```sh
nix run .#write-flake
```

If a broken generated input graph prevents the normal writer from evaluating,
run `./nucleus/bootstrap.sh` to install the minimal bootstrap source and
regenerate without validation. Then inspect the declarations and run the normal
writer again.

#### ./*/README.md

Readme files in subfolders are generated from `/**` doc-strings in `*.nix` files by running:

```sh
nix run .#mkflakedocs
```
