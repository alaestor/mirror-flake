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

  # The NAS feature marks these mounts `nofail`, so an unavailable NAS never
  # becomes a boot dependency.
  nas = {
    cauldron.enable = true;
    vault.enable = true;
    pocket.enable = true;
  };

  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = [
      "networkmanager"
      "wheel"
      "systemd-journal"
    ];
    # INTENTIONAL/TEMPORARY: public bootstrap credential, confirmed with the
    # owner. World-readable in the Nix store; replace it immediately after
    # install, same caveat as impermanence above.
    initialPassword = "changeme";
  };
}
