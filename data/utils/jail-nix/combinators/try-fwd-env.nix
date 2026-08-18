# (Originally from sourcehut:~alexdavid/jail.nix/404e7da9da5ab9aa643666682b2ba1312fa5fbe8 GPL-3.0)
{
  combinators,
  helpers,
  pkgs,
  ...
}:
let
  inherit (combinators) unsafe-add-raw-args;
in
{
  sig = "String -> Permission";
  doc = ''
    Forwards the specified environment variable to the underlying process (if set).
  '';
  impl =
    name:
    assert pkgs.lib.isValidPosixName name;
    unsafe-add-raw-args "\${${name}+--setenv ${name} \"\${${name}}\"}";
}
