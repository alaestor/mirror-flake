{ inputs, ... }:
{
  imports = [ inputs.flake-file.flakeModules.dendritic ];
  flake-file.description = "Alaestor Weissman's personal flake";
}
