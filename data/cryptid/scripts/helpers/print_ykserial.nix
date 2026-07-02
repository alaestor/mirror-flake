{ context }:
with context;
{
  name = "print_ykserial";
  description = "print the YubiKey serial";
  category = "helper";
  wrapped = false;
  hidden = false;
  content = ''
      set -eo pipefail
      ${bash-get-yubiserial}
      echo ${"$" + env.yubi.serial}
  '';
}
