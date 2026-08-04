{ inputs, ... }:
{
  flake.modules.homeManager.phone = {
    imports = [ inputs.self.modules.homeManager.ssh-client ];
    programs.home-manager.enable = true;
  };
}
