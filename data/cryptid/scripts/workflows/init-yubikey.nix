{ context }:
with context;
{
  name = "init-yubikey";
  description = "provision yubikey, create resident keys";
  category = "greater";
  wrapped = true;
  hidden = false;
  content = ''
    if [ -f ${path-firsttimeflag} ]; then
        printf "Error: '${path-firsttimeflag}' exists; dirty environment.\nIt's strongly recommended that you reboot to validate the recovery paths.\nAlternatively, you can run 'init-yubikey-dirty'.\nAborting.\n" >&2
        return 1
    fi
    # validate recovery paths
    source vault-open
    source gpg-restore
    source gpg-test
    source ssh-emerg-test
    source age-emerg-test
    # provision yubikey, pgp subkeys, age keys, ssh keys.
    source yubi-reset
    source yubi-new-ssh
    source yubi-new-age
    source yubi-move-keys
    source age-mergepubs
    source ssh-mergepubs
    source vault-close
  '';
}
