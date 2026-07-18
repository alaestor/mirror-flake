{ inputs, ... }:
{
  homeProfile.workstation.modules = [
    inputs.self.modules.homeManager.standard-terminal
    {
      programs.home-manager.enable = true;
    }
  ];
}
