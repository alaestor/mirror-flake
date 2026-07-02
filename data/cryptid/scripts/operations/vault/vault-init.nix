{ context }:
with context;
{
  name = "vault-init";
  description = "initialize the persistent vault";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
    if [ -f "${path-vault-file}" ]; then
      echo "Error: vault already exists." >&2
      return 1;
    fi
    ${bash-ask-confirm-pass "VAULTPASS" "new vault"}
    echo Creating vault ...
    creation_args=(
      --text
      --create "${path-vault-file}"
      --volume-type "normal"
      --filesystem "${vault-fs}"
      --hash "${vault-hasher}"
      --encryption "${vault-crypto}"
      --size "${vault-size}"
      --password "${"$" + env.vaultpass}"
      --pim "${vault-pim}"
      --keyfiles ""
      --random-source=/dev/urandom
    )
    sudo veracrypt "''${creation_args[@]}"
  '';
}
