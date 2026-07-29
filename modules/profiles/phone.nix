{ inputs, ... }:
{
  homeProfile.phone.modules = [
    inputs.self.modules.homeManager.ssh-client
    {
      programs.home-manager.enable = true;
    }
  ];
}
