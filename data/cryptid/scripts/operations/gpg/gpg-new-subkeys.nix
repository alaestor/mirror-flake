{ context }:
with context;
{
  name = "gpg-new-subkeys";
  description = "create new sign and encrypt subkeys";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
    ${bash-get-keyid}
    echo "Creating sign subkey ..."
    gpg -q --quick-add-key --pinentry-mode=loopback --passphrase "" "${"$" + env.keyid}" "${pgp-sign-algorithm}" sign "${pgp-expiry-in-months}m"
    echo "Creating encrypt subkey ..."
    gpg -q --quick-add-key --pinentry-mode=loopback --passphrase "" "${"$" + env.keyid}" "${pgp-encrypt-algorithm}" encrypt "${pgp-expiry-in-months}m"
  '';
}
