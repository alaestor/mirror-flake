{ context }:
with context;
{
  name = "rotate-all";
  description = "rotate all keys (except pgp root identity)";
  category = "greater";
  wrapped = true;
  hidden = false;
  content = ''
    source vault-open
    source load-secrets
    source age-emerg-make
    source age-emerg-test
    source yubi-new-age
    source age-mergepubs
    source ssh-emerg-make
    source ssh-emerg-test
    source yubi-new-ssh
    source ssh-mergepubs
    source gpg-restore
    source gpg-rev-subkeys
    source gpg-new-subkeys
    source gpg-backup
    source yubi-move-keys
    source list-pgp
    source list-ssh
    source list-age
    source vault-close
  '';
}
