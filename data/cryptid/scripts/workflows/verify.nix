{ context }:
with context;
{
  name = "verify";
  description = "run all tests";
  category = "greater";
  wrapped = true;
  hidden = false;
  content = ''
    source vault-open
    source gpg-test
    source ssh-emerg-test
    source age-emerg-test
    source vault-close
  '';
}
