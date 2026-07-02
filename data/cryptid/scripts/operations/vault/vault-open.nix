{ context }:
with context;
{
  name = "vault-open";
  description = "open the persistent vault";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
    if veracrypt --text --list | grep -q "${path-mount-vault}"; then
      echo "Vault is open."
      return 0
    fi
    [[ -z "${"$" + env.vaultpass}" ]] && read -rsp "Enter existing vault password: " ${env.vaultpass}
    echo Opening vault ...
    sudo mkdir -p ${path-mount-vault}
    mounting_args=(
      --text
      --mount "${path-vault-file}"
      --password "${"$" + env.vaultpass}"
      --pim "${vault-pim}"
      --keyfiles ""
      --protect-hidden no
      "${path-mount-vault}"
    )
    sudo veracrypt "''${mounting_args[@]}"
    mkdirs
    sudo bash -c '
      chmod -R u+rX "${path-mount-persist}"
      chown -R user:wheel "${path-mount-persist}"
      chmod -R u+rwX,g+rwX,o-rwx "${path-mount-persist}"
    '
  '';
}
