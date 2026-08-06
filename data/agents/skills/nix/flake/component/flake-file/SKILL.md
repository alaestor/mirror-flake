---
name: nix-flake-component-flake-file
description: Declaring flake inputs via flake-file, regenerating flake.nix, and recovering from a bad state (DEPRECATED).
license: MIT
disable-model-invocation: true
---

# flake-file: Declaring Inputs in Modules

Declare flake inputs with `flake-file.inputs.<name>` using its typed input schema. These are ordinary Nix module options, so use the full Nix language, including `lib.mkDefault`, interpolation, and conditionals. `flake-file` aggregates them into the generated `flake.nix`.

For example:
```nix
# nixpkg-inputs.nix
{ config, lib, ... }: {

  options.common = {
    nixpkgs-stable-version = lib.mkOption {
      type = lib.types.str;
      default = "26.05";
      description = "The version to which 'stable-nixpkgs' should be set.";
    };
  };

  config = {
    flake-file.inputs = {
      stable-nixpkgs.url   = "nixpkgs/nixos-${config.common.nixpkgs-stable-version}";
      unstable-nixpkgs.url = "nixpkgs/nixos-unstable";
    };
  };
}
```

Run `nix run .#write-flake` after adding or changing inputs to regenerate `flake.nix`.

## Recovering a broken flake

`nix run .#write-flake` may become unavailable when invalid inputs or configuration prevent the flake from evaluating. Temporarily use a minimal bootstrap `flake.nix` to restore evaluation, then rerun the generator:

```nix
# minimal bootstrap flake
{
  # Adapt the module path to the project.
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    flake-file.url = "github:denful/flake-file";
    import-tree.url = "github:denful/import-tree";
  };
}
```
