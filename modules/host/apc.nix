{ inputs, ... }:
{
  host.apc = rec {
    description = "APC desktop workstation.";
    primaryUser = "user";
    stateVersion = "24.05";

    # TODO(hosts): abstract path indirection
  
    userEnvironment.${primaryUser} = {
      mode = "standalone";
      modules = [
        inputs.self.modules.homeManager.workstation
        inputs.self.modules.homeManager.alaestor
        ../../hosts/apc/home/plasma.nix
        ../../hosts/apc/home/user.nix
      ];
    };

    modules =
      (with inputs.self.modules.nixos; [
        auto-login
        crypto-yubikey
        hifi-audio
        kde
        nas
        printers
        serve-nix-cache
        ssh-client
        ssh-host
        tailnet-client
      ])
      ++ [
        ../../hosts/apc/hardware.nix
        (import ../../hosts/apc/networking.nix { inherit inputs; })
        (import ../../hosts/apc/system.nix { inherit inputs; })
      ];
  };
}
