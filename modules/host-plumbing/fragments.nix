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
  self,
  ...
}:
{
  config.flake.lib.importHostFragments =
    name:
    import "${self}/hosts/${name}" {
      inherit inputs self;
      fleet = config.flake.fleet;
    };
}
