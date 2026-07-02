{ context }:
with context;
{
  name = "gpg-backup";
  description = "export keys to vault";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
    ${bash-get-keyid}
    echo Creating GPG backup ...
    OUT_PRI=$(timestamped_now "${pathv-pgp-private}")
    OUT_REV=$(timestamped_now "${pathv-pgp-revoke}")
    OUT_PUB=$(timestamped_now "${pathv-pgp-public}")

    TMP_PRI=$(mktemp /tmp/gpg-secret.XXXXXX)
    gpg --yes --batch --export-secret-keys --armor ${"$" + env.keyid} > "$TMP_PRI"
    if [[ ! -s "$TMP_PRI" ]]; then
      echo "Error: Secret keys export failed (file is empty or missing)" >&2
      exit 1
    fi
    mv "$TMP_PRI" "$OUT_PRI"

    echo "Saved secret keys to: '$OUT_PRI'"
    TMP_REV=$(mktemp /tmp/gpg-revoke.XXXXXX)
    rm -rf "$TMP_REV"
    expect -d << EXPECT_SCRIPT &> ${path-log-expectScript}
    ${expect-header}
    spawn gpg --output "$TMP_REV" --gen-revoke "${"$" + env.keyid}"
    oi "Create a revocation certificate" "y"
    safe_expect "0 = No reason specified"
    oi "Your decision?" "0"
    oi "optional description" ""
    oi "Is this okay" "y"
    safe_expect_end
    EXPECT_SCRIPT
    if [[ ! -s "$TMP_REV" ]]; then
      echo "Error: Revocation certificate creation failed (file is empty or missing)" >&2
      exit 1
    fi
    mv "$TMP_REV" "$OUT_REV"
    echo "Saved revoke certificate to: '$OUT_REV'"

    TMP_PUB=$(mktemp /tmp/gpg-pub.XXXXXX)
    gpg --export --armor ${"$" + env.keyid} > "$TMP_PUB"
    if [[ ! -s "$TMP_PUB" ]]; then
      echo "Error: public key export failed (file is empty or missing)" >&2
      exit 1
    fi
    mv "$TMP_PUB" "$OUT_PUB"
    echo "Saved public keys to: $OUT_PUB"
  '';
}
