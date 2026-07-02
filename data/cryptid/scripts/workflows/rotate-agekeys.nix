{ context }:
with context;
{
  name = "rotate-agekeys";
  description = "make new resident and breakglass age keys";
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
    source list-age
    source vault-close
  '';
}
