{ context }:
with context;
{
  name = "first-time-init";
  description = "create vault, PGP, AGE, emergency keys";
  category = "greater";
  wrapped = true;
  hidden = false;
  content = ''
    # make vault
    source vault-init
    source vault-open
    # make root key
    source gpg-new-rootkey
    source gpg-new-subkeys
    source gpg-backup
    # make "breakglass" emergency keys
    source ssh-emerg-make
    source ssh-emerg-test
    source age-emerg-make
    source age-emerg-test
    # lockup and prep for shutdown
    source vault-close
    touch ${path-firsttimeflag}
    printf "\n\n---\nDone. Please reboot and run 'init-yubikey' to complete initialization.\n"
  '';
}
