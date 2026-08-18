# (Originally from sourcehut:~alexdavid/jail.nix/404e7da9da5ab9aa643666682b2ba1312fa5fbe8 GPL-3.0)
{ combinators, ... }:
let
  inherit (combinators) try-ro-bind;
in
{
  sig = "String -> Permission";
  doc = ''
    Binds the specified path in the jail as read-only if it exists.
  '';
  impl = path: try-ro-bind path path;
}
