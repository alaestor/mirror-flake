{ inputs, ... }:
{
  # TODO: this is a featureset
  flake.modules.homeManager.coding = {
    imports = with inputs.self.modules.homeManager; [
      pgp
      git
      ai-coding
    ];
  };
}
