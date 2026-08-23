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
        printers
        serve-nix-cache
        ssh-client
        ssh-host
        steam-gaming
        tailnet-client
      ])
      ++ hostFragments.nixos;
  };
}
