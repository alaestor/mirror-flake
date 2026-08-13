/**
  The offline identity toolkit: the script catalog from `data/cryptid` rendered
  against this host's constants, plus the platform modules the catalog assumes.
*/
{ self }:
{ config, lib, pkgs, cryptidConstants, ... }:
let
  username = config.hostIdentity.primaryUser;
  scriptContext = cryptidConstants // import (self.data.path "cryptid/script-context.nix") {
    constants = cryptidConstants;
    inherit username;
  };
  scriptCatalog = import (self.data.path "cryptid") {
    inherit lib pkgs;
    context = scriptContext;
  };

in {

  # platform
  imports = with self.modules.nixos; [
    isolive
    airgap
    # not using cryptos from flake; micromanage dependencies
  ];
  environment.etc."issue".text = scriptCatalog.helpText;
  environment.interactiveShellInit = scriptContext.bash-make-gnupg-home;
  environment.systemPackages = scriptCatalog.packages;
}
