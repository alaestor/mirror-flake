{ context }:
with context;
{
  name = "list-pgp";
  description = "list most recent PGP keys";
  category = "helper";
  wrapped = true;
  hidden = false;
  content = ''
    printf "\nYUBI: OpenPGP\n"
    ykman openpgp info
    printf "\nGPG: Card Status\n"
    gpg --card-status
    printf "\nGPG: Secret Keys\n"
    gpg -K --with-keygrip
  '';
}
