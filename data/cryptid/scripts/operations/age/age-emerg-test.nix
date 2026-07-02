{ context }:
with context;
{
  name = "age-emerg-test";
  description = "verify emergency age backup";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
    PRIV_PATH=$(timestamped_last "${pathv-emerg-age-private}")
    PUB_PATH=$(timestamped_last "${pathv-emerg-age-public}")
    printf "Verifying emergency AGE keys...\nPrivate: $PRIV_PATH\nPublic:  $PUB_PATH\n"
    OUTPUT=$(age-keygen -y "$PRIV_PATH")
    if [ "$OUTPUT" == "$(cat "$PUB_PATH")" ]; then echo "TEST PASSED"; else echo "FAIL: AGE CORRUPT OR INVALID" >&2; fi
  '';
}
