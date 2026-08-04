{ lib }:
let
  compact =
    value:
    if builtins.isAttrs value then
      lib.filterAttrs (_: child: child != null && child != { }) (lib.mapAttrs (_: compact) value)
    else
      value;
in
{
  description,
  inputs,
  outputsExpression ? ''
    inputs:
      inputs.flake-parts.lib.mkFlake { inherit inputs; } {
        imports = [ ./nucleus/flake-module.nix ]
          ++ import ./nucleus/list-modules.nix ./modules;
      }
  '',
}:
''
  # DO-NOT-EDIT. Generated from nucleus declarations.
  {
    description = ${builtins.toJSON description};

    outputs = ${outputsExpression};

    inputs = ${lib.generators.toPretty { } (compact inputs)};
  }
''
