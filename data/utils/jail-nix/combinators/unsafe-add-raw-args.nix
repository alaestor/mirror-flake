# (Originally from sourcehut:~alexdavid/jail.nix/404e7da9da5ab9aa643666682b2ba1312fa5fbe8 GPL-3.0)
{ ... }:
{
  sig = "String -> Permission";
  doc = ''
    Adds the raw string passed into it into the call to bubblewrap.

    Nothing is escaped, it is the caller's responsibility to ensure
    everything is properly escaped.
  '';
  impl = args: state: state // { cmd = "${state.cmd} ${args}"; };
}
