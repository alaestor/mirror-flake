{ config, inputs, self, ... }:
let
  hostFragments = import "${self}/hosts/lanser" {
    inherit inputs;
    tailnet = config.flake.fleet.tailnets."0x04cc";
  };
in
{
  host.lanser = rec {
    description = "Home server and public service host.";
    primaryUser = "user";
    stateVersion = "24.11";

    userEnvironment.${primaryUser} = {
      mode = "integrated";
      modules = (with inputs.self.modules.homeManager; [
        standard-terminal
      ])
      ++ hostFragments.homeManager;
    };

    modules =
      (with inputs.self.modules.nixos; [
        agenix
        nas
        ssh-host
        server-hardening
        tailnet-client
        serve-caddy
        domain-0x04cc
        domain-remotehost
        serve-torrenting
      ])
      ++ hostFragments.nixos;
  };
}
