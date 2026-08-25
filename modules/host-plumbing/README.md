## fragments

Uniform entrypoint for a host's private fragment tree.

Each `hosts/<name>/default.nix` is a function of one attribute set that returns
the host's fragment lists keyed by module class. Every entrypoint receives the
same arguments, so a fragment tree can grow a new dependency without changing
its call site; entrypoints ignore what they do not use with `{ ... }`.

```nix
# hosts/example/default.nix
{ fleet, inputs, ... }:
{
nixos = [ ./hardware.nix (import ./system.nix { inherit inputs; }) ];
homeManager = [ ./home/user.nix ];
}
```

Fleet facts are passed in rather than reached for, so private fragments never
evaluate `config.flake`.

## global-config

Global configurations included automatically into all hosts of a class.
Each class states the same intent in its own platform vocabulary; neither
export is a reusable feature, and hosts never import them explicitly.

## registry

Declarative registry for the hosts in this flake.
Each host is defined as an attribute in `config.host`, declares the module
`class` it is evaluated in, and automatically produces:
- A NixOS configuration under `flake.nixosConfigurations`, or a Nix-on-Droid
configuration under `flake.nixOnDroidConfigurations`
- Optional helper apps (ISO writer, nixos-anywhere deployer)

Every generated configuration is pre-composed with the `host-identity` module
of its class, so that each host inherits a consistent identity; NixOS hosts
additionally inherit the common `global-config` base settings.

Hosts may also attach Home Manager environments under `userEnvironment`.
Feature-contributed and explicitly attached modules are composed identically for
integrated, standalone, and Nix-on-Droid activation.

Provides a per-host option schema to configure options related to
hostIdentity, along with nixpkgs, system, and modules.

Set host configuration capabilities such as enabling the `nix run`
`deploy` nixosAnywhere scripts, or `mkBootable` ISO scripts. These
helper outputs are generated for NixOS hosts only.

Plumbs the `hosts` into the configuration output of their class and the
associated `apps` (depending on enabled capabilities)
