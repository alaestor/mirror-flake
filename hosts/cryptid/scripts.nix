/**
  The offline identity toolkit: the script catalog from `data/cryptid` rendered
  against this host's constants. The platform modules (`isolive`, `airgap`)
  the catalog assumes are listed in `modules/host/cryptid.nix`, alongside
  every other host's module list.
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
  environment.etc."issue".text = scriptCatalog.helpText;
  environment.interactiveShellInit = scriptContext.bash-make-gnupg-home;
  environment.systemPackages = scriptCatalog.packages;
}
