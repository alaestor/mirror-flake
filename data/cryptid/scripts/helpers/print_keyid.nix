{ context }:
with context;
{
  name = "print_keyid";
  description = "print the first private PGP signature";
  category = "helper";
  wrapped = false;
  hidden = false;
  content = ''
    set -eo pipefail
    ${bash-get-keyid}
    echo ${"$" + env.keyid}
  '';
}
