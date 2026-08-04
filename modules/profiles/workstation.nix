{ inputs, ... }:
{
  flake.modules.homeManager.workstation = {
    imports = [
      inputs.self.modules.homeManager.standard-terminal
      inputs.self.modules.homeManager.ssh-client
      inputs.self.modules.homeManager.coding
      inputs.self.modules.homeManager.librewolf
      inputs.self.modules.homeManager.discord
      inputs.self.modules.homeManager.mpv
    ];

    programs.home-manager.enable = true;
  };
}
