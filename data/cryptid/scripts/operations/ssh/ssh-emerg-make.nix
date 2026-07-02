{ context }:
with context;
{
  name = "ssh-emerg-make";
  description = "create and backup emergency ssh key";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
    echo Generating emergency SSH key ...
    TMP_DIR=$(mktemp -d)
    TMP_FILE="$TMP_DIR/sshkey"
    TMP_PRI="$TMP_FILE"
    TMP_PUB="''${TMP_FILE}.pub"
    OUT_PRI=$(timestamped_now "${pathv-emerg-ssh-private}")
    OUT_PUB=$(timestamped_now "${pathv-emerg-ssh-public}")

    ssh-keygen -t ed25519 -C "${emergency-label-ssh}" -f "$TMP_FILE" -N ""

    if [[ ! -s "$TMP_PRI" ]]; then
      echo "Error: private key creation failed (file is empty or missing)" >&2
      exit 1
    fi
    if [[ ! -s "$TMP_PUB" ]]; then
      echo "Error: public key creation failed (file is empty or missing)" >&2
      exit 1
    fi
    mv "$TMP_PRI" "$OUT_PRI"
    mv "$TMP_PUB" "$OUT_PUB"
    printf "Saved private key to: '$OUT_PRI'\nSaved public key to: '$OUT_PUB'\n"
  '';
}
