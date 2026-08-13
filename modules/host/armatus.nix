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
      ] ++ hostFragments.homeManager;
    };

    modules = (with inputs.self.modules.nixos; [
      kde
      auto-login
      crypto-yubikey
      hifi-audio
      printers
      nas
      ssh-client
      ssh-host
      standard-disk
    ])
    ++ hostFragments.nixos;
  };
}
