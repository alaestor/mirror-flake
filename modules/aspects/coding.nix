/**
  Home Manager aspect for a coding environment.

  This composes developer-oriented capabilities without introducing a new
  configuration interface of its own.
*/
{ inputs, ... }:
{
  flake.modules.homeManager.coding = {
    imports = with inputs.self.modules.homeManager; [
      pgp
      git
      ai-coding
      ai-coding-local
      vscodium
    ];
  };
}
