{ context }:
with context;
{
  name = "vault-cd";
  description = "change directory to vault mount";
  category = "lesser";
  wrapped = false;
  hidden = false;
  content = ''
    cd "${path-mount-vault}"
  '';
}
