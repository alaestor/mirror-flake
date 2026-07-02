{ context }:
with context;
{
  name = "init-yubikey-dirty";
  description = "Resume YubiKey initialization without rebooting.";
  category = "internal";
  wrapped = true;
  hidden = true;
  content = ''
    echo "Deleting GPG state ..."
    source gpg-clean
    rm -rf "${path-firsttimeflag}"
    source init-yubikey
    touch "${path-firsttimeflag}"
  '';
}
