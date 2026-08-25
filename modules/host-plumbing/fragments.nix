/**

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

*/
{
  config,
  inputs,
  lib,
  self,
  ...
}:
let
  # Gives the documented contract ("returns the host's fragment lists keyed
  # by module class") teeth: a missing class defaults to [], and a typo
  # (e.g. `nixOS = [...]`) fails loudly with "not declared" instead of the
  # fragments silently never loading and the host still building.
  fragmentSchema =
    { lib, ... }:
    {
      options = {
        nixos = lib.mkOption {
          type = lib.types.listOf lib.types.unspecified;
          default = [ ];
          description = "This host's NixOS module fragments.";
        };
        homeManager = lib.mkOption {
          type = lib.types.listOf lib.types.unspecified;
          default = [ ];
          description = "This host's Home Manager module fragments.";
        };
        nixOnDroid = lib.mkOption {
          type = lib.types.listOf lib.types.unspecified;
          default = [ ];
          description = "This host's Nix-on-Droid module fragments.";
        };
      };
    };
in
{
  config.flake.lib.importHostFragments =
    name:
    (lib.evalModules {
      modules = [
        fragmentSchema
        (import "${self}/hosts/${name}" {
          inherit inputs self;
          fleet = config.flake.fleet;
        })
      ];
    }).config;
}
