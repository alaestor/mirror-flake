{ context }:
with context;
{
  name = "ssh-mergepubs";
  description = "yubi+breakglass -> 'authorized_keys'";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
      SK=$(timestamped_last "${pathv-ssh-public}")
      EM=$(timestamped_last "${pathv-emerg-ssh-public}")
      OUT=$(timestamped_now "${pathv-merged-pubs-ssh}")
      TMP_PUB=$(mktemp /tmp/merge-ssh.XXXXXX)
      cat "$SK" "$EM" >> "$TMP_PUB"
      mv "$TMP_PUB" "$OUT"
      echo "Created ssh public-keys file: '$OUT'"
  '';
}
