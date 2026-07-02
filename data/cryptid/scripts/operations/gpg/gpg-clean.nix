{ context }:
with context;
{
  name = "gpg-clean";
  description = "delete and recreate the gpg folder";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
      gpgconf --kill gpg-agent 2>/dev/null || true
      if [ -d "$GNUPGHOME" ]; then
        rm -rf "$GNUPGHOME"
      fi
      ${bash-make-gnupg-home}
      echo "Refreshed $GNUPGHOME"
  '';
}
