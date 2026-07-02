{ context }:
with context;
{
  name = "ssh-emerg-test";
  description = "verify emergency ssh backup";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
    PRIV_PATH=$(timestamped_last "${pathv-emerg-ssh-private}")
    PUB_PATH=$(timestamped_last "${pathv-emerg-ssh-public}")
    printf "Verifying emergency SSH keys...\nPrivate: $PRIV_PATH\nPublic:  $PUB_PATH\n"
    OUTPUT=$(ssh-keygen -y -f "$PRIV_PATH")
    if [ "$OUTPUT" = "$(cat "$PUB_PATH")" ]; then echo "TEST PASSED"; else echo "FAIL: SSH CORRUPT OR INVALID" >&2; fi
  '';
}
