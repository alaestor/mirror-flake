/**
  armatus: laptop. Declares its host record: modules, capabilities, and
  the standalone Home Manager environment.
*/
{ config, inputs, ... }:
let
  hostFragments = config.flake.lib.importHostFragments "armatus";
in
{
  host.armatus = rec {
    description = "Laptop. Dell Precision 17 7720; 7820HQ+64GB, P5000+16GB, 512GB:NVMe.";
    primaryUser = "user";
    stateVersion = "26.11";
    capabilities.nixosAnywhere = true;

    userEnvironment.${primaryUser} = {
      mode = "integrated";
      modules = [
        inputs.self.modules.homeManager.workstation
        inputs.self.modules.homeManager.alaestor
        inputs.self.modules.homeManager.alaestor-plasma
      ] ++ hostFragments.homeManager;
    };

    modules = (with inputs.self.modules.nixos; [
      kde
      auto-login
      crypto-yubikey
      hifi-audio
      printer-brother-hl-l2320d
      nas
      ssh-client
      ssh-host
      standard-disk
    ])
    ++ hostFragments.nixos;
  };
}
