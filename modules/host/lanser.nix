/**
  lanser: home server and public service host. Declares its host record:
  modules, capabilities, and the integrated Home Manager environment.
*/
{ config, inputs, ... }:
let
  hostFragments = config.flake.lib.importHostFragments "lanser";
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
        local-cache
        nas
        ssh-host
        server-hardening
        tailnet-client
        serve-caddy
        domain-0x04
        domain-bokunopi
        domain-remotehost
        serve-torrenting
      ])
      ++ hostFragments.nixos;
  };
}
