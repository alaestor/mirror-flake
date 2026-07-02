{ context }:
with context;
{
  name = "extend-subkeys";
  description = "extend PGP subkeys";
  category = "greater";
  wrapped = true;
  hidden = false;
  content = ''
    source vault-open
    source load-secrets
    source gpg-restore
    source yubi-extend
    source list-pgp
    source vault-close
  '';
}
