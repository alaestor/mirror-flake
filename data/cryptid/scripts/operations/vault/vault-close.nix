{ context }:
with context;
{
  name = "vault-close";
  description = "close the persistent vault";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
    # set persist to be read-only by user
    sudo chown -R user:wheel "${path-mount-persist}"
    sudo chmod -R u+rX,go-rwx "${path-mount-persist}"
    # unmount
    sudo veracrypt --text --unmount "${path-mount-vault}"
    sync
  '';
}
