{ config, ... }:
let
  username = config.hostIdentity.primaryUser;
in
{
  ssh-host = {
    allowUsers = [ username ];
    initrd.enable = true;
  };

  standard-disk.impermanence = {
    # INTENTIONAL/TEMPORARY: disabled while this host is still being set up;
    # confirmed with the owner, not an oversight. Re-enable (`true`) once
    # armatus's install is finished.
    enable = false; #true;
    persist.users.${username}.directories = [ ".ssh" ];
  };

  /*nas = {
    cauldron.enable = true;
    vault.enable = true;
    pocket.enable = true;
    };*/

  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = [
      "wheel"
      "systemd-journal"
    ];
    # INTENTIONAL/TEMPORARY: public bootstrap credential, confirmed with the
    # owner. World-readable in the Nix store; replace it immediately after
    # install, same caveat as impermanence above.
    initialPassword = "changeme";
  };
}
