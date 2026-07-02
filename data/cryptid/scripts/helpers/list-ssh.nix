{ context }:
with context;
{
  name = "list-ssh";
  description = "list most recent ssh identities";
  category = "helper";
  wrapped = true;
  hidden = false;
  content = ''
    source load-secrets
    echo "YUBI: FIDO credentials"
    ykman fido credentials list --pin "${"$" + env.yubi.fido.pin}"
    FILE=$(timestamped_last "${pathv-emerg-ssh-public}")
    echo "Most recent SSH Breakglass: $FILE"
    cat $FILE
  '';
}
