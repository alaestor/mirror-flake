{ context }:
with context;
{
  name = "load-secrets";
  description = "load most recent PINs / passcodes";
  category = "helper";
  wrapped = true;
  hidden = false;
  content = ''
    YUBI_FILE=$(timestamped_last "${pathv-yubicodes}")
    source $YUBI_FILE
    printf "Loaded:\n\t$YUBI_FILE\n\n"
  '';
}
