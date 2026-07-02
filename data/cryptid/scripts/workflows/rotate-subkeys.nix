{ context }:
with context;
{
  name = "rotate-subkeys";
  description = "revoke PGP subkeys and generate new ones";
  category = "greater";
  wrapped = true;
  hidden = false;
  content = ''
    source vault-open
    source load-secrets
    source gpg-restore
    source gpg-rev-subkeys
    source gpg-new-subkeys
    source gpg-backup
    source yubi-move-keys
    source list-pgp
    source vault-close
  '';
}
