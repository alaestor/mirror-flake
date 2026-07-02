{ context }:
with context;
{
  name = "list-yubicodes";
  description = "list most recent YubiKey PINs";
  category = "helper";
  wrapped = true;
  hidden = false;
  content = ''
    YUBI_FILE=$(timestamped_last "${pathv-yubicodes}")
    printf "\nYUBI: passcodes in $YUBI_FILE \n"
    cat $YUBI_FILE
  '';
}
