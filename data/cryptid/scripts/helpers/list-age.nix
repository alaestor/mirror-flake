{ context }:
with context;
{
  name = "list-age";
  description = "list most recent age identities";
  category = "helper";
  wrapped = true;
  hidden = false;
  content = ''
    echo "YUBI: PIV Slots"
    ykman piv info
    FILE=$(timestamped_last "${pathv-emerg-age-public}")
    echo "Most recent breakglass: $FILE"
    cat $FILE
  '';
}
