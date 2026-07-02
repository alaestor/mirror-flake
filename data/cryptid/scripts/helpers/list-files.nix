{ context }:
with context;
{
  name = "list-files";
  description = "list contents of persist and vault";
  category = "helper";
  wrapped = false;
  hidden = false;
  content = ''
    set -eo pipefail
    printf "\n${path-mount-persist}/\n"
    find "${path-mount-persist}/." -print | sed -e 's;[^/]*/;|____;g;s;____|; |;g'
    if veracrypt --text --list | grep -q "${path-mount-vault}"; then
      printf "\n${path-mount-vault}/\n"
      find "${path-mount-vault}/." -print | sed -e 's;[^/]*/;|____;g;s;____|; |;g'
    else
      echo "Vault not open."
    fi
  '';
}
