{ context }:
with context;
{
  name = "gpg-test";
  description = "verify root key";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
    OLDHOME=$GNUPGHOME
    cleanup() {
        export GNUPGHOME="$OLDHOME"
    }
    trap cleanup EXIT ERR
    PRIV_PATH=$(timestamped_last "${pathv-pgp-private}")
    PUB_PATH=$(timestamped_last "${pathv-pgp-public}")
    printf "Verifying PGP root key...\nPrivate: $PRIV_PATH\nPublic:  $PUB_PATH\n"
    GNUPGHOME=$(mktemp -d)
    gpg --batch --import "$PRIV_PATH"
    ${bash-get-keyid}
    OUTPUT=$(mktemp /tmp/gpg-pub.XXXXXX)
    gpg --export --armor ${"$" + env.keyid} > "$OUTPUT"
    if [ "$(cat "$OUTPUT")" = "$(cat "$PUB_PATH")" ]; then echo "TEST PASSED"; else echo "FAIL: PGP CORRUPT OR INVALID" >&2; fi
    cleanup
    trap "" EXIT ERR
  '';
}
