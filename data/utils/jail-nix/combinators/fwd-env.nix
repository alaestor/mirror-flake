# (Originally from sourcehut:~alexdavid/jail.nix/404e7da9da5ab9aa643666682b2ba1312fa5fbe8 GPL-3.0)
{ combinators, helpers, ... }:
let
  inherit (combinators) set-env;
in
{
  sig = "String -> Permission";
  doc = ''
    Forwards the specified environment variable to the underlying process.

    If the env var is not set when the jailed application is run, it will
    exit non-zero.

    If you want to be tolerant of the environment being unset, use
    [try-fwd-env](#try-fwd-env) instead.
  '';
  impl = name: set-env name (helpers.noescape "\"\$${name}\"");
}
