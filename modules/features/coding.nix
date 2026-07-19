{ inputs, ... }:
{
  flake.modules.homeManager.coding = {
    imports = with inputs.self.modules.homeManager; [
      pgp
      git
      ai-coding
    ];
  };
}
