{ context }:
with context;
{
  name = "age-emerg-make";
  description = "create and backup emergency age key";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
    echo Generating emergency AGE key ...
    TMP_DIR=$(mktemp -d)
    TMP_FILE="$TMP_DIR/agekey"
    TMP_PRI="$TMP_FILE"
    TMP_PUB="''${TMP_FILE}.pub"
    OUT_PRI=$(timestamped_now "${pathv-emerg-age-private}")
    OUT_PUB=$(timestamped_now "${pathv-emerg-age-public}")

    age-keygen -pq -o "$TMP_PRI"
    age-keygen -y $TMP_PRI > "$TMP_PUB"

    mv "$TMP_PRI" "$OUT_PRI"
    mv "$TMP_PUB" "$OUT_PUB"
    printf "Saved private key to: '$OUT_PRI'\nSaved public key to: '$OUT_PUB'\n"
  '';
}
