{ context }:
with context;
{
  name = "yubi-extend";
  description = "extend all subkeys by ${pgp-expiry-in-months} months";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
    gpg --card-status
    gpg -K
    ${bash-get-keyid}
    gpg --quick-set-expire ${"$" + env.keyid} '${pgp-expiry-in-months}m' '*'
    echo "Current subkeys:"
    gpg --list-secret-keys --keyid-format LONG "${"$" + env.keyid}"
  '';
}
