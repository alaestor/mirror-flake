/**
  apc: primary desktop workstation. Declares its host record: modules,
  capabilities, and the standalone Home Manager environment.
*/
{ config, inputs, ... }:
let
  hostFragments = config.flake.lib.importHostFragments "apc";
in
{
  host.apc = rec {
    description = "APC desktop workstation.";
    primaryUser = "user";
    stateVersion = "24.05";

    userEnvironment.${primaryUser} = {
      mode = "standalone";
      modules = [
        inputs.self.modules.homeManager.workstation
        inputs.self.modules.homeManager.alaestor
        inputs.self.modules.homeManager.alaestor-plasma
      ] ++ hostFragments.homeManager;
    };

    modules =
      (with inputs.self.modules.nixos; [
        agent-vm
        auto-login
        crypto-yubikey
        hifi-audio
        kde
        memory-manager
        nas
        printer-brother-hl-l2320d
        serve-nix-cache
        server-hardening
        ssh-client
        ssh-host
        steam-gaming
        tailnet-client
      ])
      ++ hostFragments.nixos;
  };
}
