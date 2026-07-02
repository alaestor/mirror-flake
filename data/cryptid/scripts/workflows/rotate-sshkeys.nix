{ context }:
with context;
{
  name = "rotate-sshkeys";
  description = "make new resident and breakglass ssh keys";
  category = "greater";
  wrapped = true;
  hidden = false;
  content = ''
    source vault-open
    source load-secrets
    source ssh-emerg-make
    source ssh-emerg-test
    source yubi-new-ssh
    source ssh-mergepubs
    source list-ssh
    source vault-close
  '';
}
