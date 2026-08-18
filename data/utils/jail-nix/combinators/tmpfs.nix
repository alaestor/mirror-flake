# (Originally from sourcehut:~alexdavid/jail.nix/404e7da9da5ab9aa643666682b2ba1312fa5fbe8 GPL-3.0)
{ combinators, helpers, ... }:
let
  inherit (combinators) unsafe-add-raw-args;
in
{
  sig = "String -> Permission";
  doc = ''
    Mounts a new tmpfs at the specified location.
  '';
  impl = path: unsafe-add-raw-args "--tmpfs ${helpers.escape path}";
}
