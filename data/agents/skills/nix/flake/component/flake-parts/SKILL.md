---
name: nix-flake-component-flake-parts
description: Define packages, apps, checks, dev shells, modules, and other flake outputs using flake-parts modules
license: MIT
disable-model-invocation: false
---

# flake-parts

A flake-parts module is an ordinary Nix module evaluated by `flake-parts.lib.mkFlake` to construct flake outputs. It supports the normal module system, including options, `config`, `imports`, merging, `lib.mkIf`, and `lib.mkDefault`.

Its option schema describes flake outputs rather than a NixOS or Home Manager configuration.

## Module structure

A typical module has this form:

```nix
{ inputs, lib, config, ... }:
{
  imports = [ ];

  systems = [ ];

  perSystem = { pkgs, system, ... }: {
    # System-specific outputs
  };

  flake = {
    # Top-level outputs
  };
}
```

Not every module needs to define every option.

## `imports`

Composes additional flake-parts modules.

```nix
{
  imports = [
    ./packages.nix
    ./checks.nix
  ];
}
```

Imported modules participate in the same option evaluation and merging process.

## `systems`

Declares the systems for which `perSystem` is evaluated.

This is normally defined once near the flake root:

```nix
{
  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
}
```

Each system produces outputs such as:

```nix
packages.x86_64-linux
packages.aarch64-linux
```

## `perSystem`

Defines outputs that are indexed by system, including:

* `packages`
* `apps`
* `checks`
* `devShells`
* `formatter`

```nix
{
  perSystem = { self', inputs', pkgs, ... }: {
    packages.hello = pkgs.stdenv.mkDerivation {
      pname = "hello";
      version = "1.0";
      # ...
    };

    apps.hello = {
      type = "app";
      program = "${self'.packages.hello}/bin/hello";
    };
  };
}
```

flake-parts places these beneath the current system automatically:

```nix
packages.${system}.hello
apps.${system}.hello
```

### `self'` and `inputs'`

Within `perSystem`, `self'` and `inputs'` are system-projected views of the current flake and its inputs.

```nix
{
  perSystem = { self', inputs', ... }: {
    packages.x = inputs'.nixpkgs.legacyPackages.hello;
    packages.y = self'.packages.x;
  };
}
```

The equivalent explicit form is:

```nix
{
  perSystem = { inputs, self, system, ... }: {
    packages.x =
      inputs.nixpkgs.legacyPackages.${system}.hello;

    packages.y =
      self.packages.${system}.x;
  };
}
```

Use the primed forms when consuming system-specific outputs inside `perSystem`.

## `flake`

Defines top-level outputs that are not automatically indexed by system.

Typical examples include:

* `nixosModules`
* `homeModules`
* `flakeModules`
* `nixosConfigurations`
* `overlays`
* `lib`

```nix
{
  flake = {
    nixosModules.default = ./module.nix;

    lib.example = {
      enabled = true;
    };
  };
}
```

Values under `flake` contribute directly to the final flake output:

```nix
self.nixosModules.default
self.lib.example
```

Prefer `perSystem` for conventional system-specific outputs. Use `flake` for top-level outputs or when constructing an output layout manually.
