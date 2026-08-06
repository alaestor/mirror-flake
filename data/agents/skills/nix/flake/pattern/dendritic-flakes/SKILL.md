---
name: nix-flake-pattern-dendritic-flakes
description: High-level overview of dendritic flake architecture using flake-parts, flake-file, and import-tree. (DEPRECATED)
license: MIT
disable-model-invocation: true
---

# About Dendritic Flakes

A *dendritic* flake organizes configuration as a tree of small feature-specific files where each leaf file is a `flake-parts` module that contributes to the flake's outputs.

It is built on three pillars:

- **[`nix-flake-component-flake-parts`](../../component/flake-parts/SKILL.md)** — the module-system backbone; each file can be a `flake-parts` module.
- **[`nix-flake-component-import-tree`](../../component/import-tree/SKILL.md)** — recursively discovers and imports every `.nix` file under a directory, so adding or removing a module is just a file operation.
- **[`nix-flake-component-flake-file`](../../component/flake-file/SKILL.md)** — generates `flake.nix` from Nix module options, so inputs and outputs are declared inside modules rather than hand-edited in `flake.nix`.

Typically, import-tree is used to recursively import everything from `./modules/`, though project structures differ.

You can run `nix flake show` during development to verify that your modules are correctly contributing to the flake's outputs and to catch simple evaluation errors early.
