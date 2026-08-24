{ config, lib, pkgs, ... }:
{

  user = {
    uid = 10229;
    gid = 10229;
  };

  ssh-host = {
    comment = "generated host key (${config.hostIdentity.name})";
    allowUsers = [ config.hostIdentity.primaryUser ];
  };

  environment.packages = with pkgs; [
    openssh
    # NOTE(compatibility): complications around age sk decryption in nix-on-droid resulting from pcsc woes; see [age-plugin-yubikey#109](https://github.com/str4d/age-plugin-yubikey/issues/109)
    age
    age-plugin-yubikey
    doggo
    curl
    ripgrep
  ];

  # `nixremote` rather than `user`: the builder-side account has to be in apc's
  # `trusted-users` for input-addressed offloading to work at all, and that is
  # root-equivalent over its store, so it is a dedicated forced-command account
  # instead of the interactive one.
  nix.extraOptions = lib.mkAfter ''
    builders = ssh://nixremote@apc.tailnet.0x04.cc aarch64-linux,x86_64-linux /data/data/com.termux.nix/files/home/.ssh/id_ed25519_noblesse 8 10
    builders-use-substitutes = true
  '';

  home-manager.backupFileExtension = "hm-bak";

  # TODO(droid): can this be generalized in base?
  environment.sessionVariables.HOSTNAME = config.hostIdentity.name;

}
