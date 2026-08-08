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
    # Public bootstrap credential; replace it immediately after install.
    initialPassword = "changeme";
  };
}
