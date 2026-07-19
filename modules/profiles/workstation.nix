{ inputs, ... }:
{
  homeProfile.workstation.modules = [
    inputs.self.modules.homeManager.standard-terminal
    inputs.self.modules.homeManager.ssh-client
    inputs.self.modules.homeManager.coding
    {
      programs.home-manager.enable = true;
    }
  ];
}
