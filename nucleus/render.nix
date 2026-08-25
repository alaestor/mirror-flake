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
  # No default: nucleus/flake-module.nix always passes a value, so a
  # default here was a second copy of the same expression that had to stay
  # byte-identical to flake-module.nix's own default, or the generated
  # flake.nix would change depending on which one won.
  outputsExpression,
}:
''
  # DO-NOT-EDIT. Generated from nucleus declarations.
  {
    description = ${builtins.toJSON description};

    outputs = ${outputsExpression};

    inputs = ${lib.generators.toPretty { } (compact inputs)};
  }
''
