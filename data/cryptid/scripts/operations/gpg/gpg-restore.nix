{ context }:
with context;
{
  name = "gpg-restore";
  description = "import keys from vault";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
    TARGET=$(timestamped_last "${pathv-pgp-private}")
    echo "Importing most recent key: $TARGET"
    # ensure the agent is running
    gpgconf --launch gpg-agent
    sleep 1
    gpg --batch --import "$TARGET"
    ${bash-get-keyid}
    echo "Imported/Found key: ${"$" + env.keyid}"
    echo "${"$" + env.keyid}:6:" | gpg --import-ownertrust
    gpg --list-secret-keys
    gpg --card-status
  '';
}
