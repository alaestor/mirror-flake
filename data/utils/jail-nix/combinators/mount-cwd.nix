# (Originally from sourcehut:~alexdavid/jail.nix/404e7da9da5ab9aa643666682b2ba1312fa5fbe8 GPL-3.0)
{ combinators, ... }:
let
  inherit (combinators)
    include-once
    unsafe-add-raw-args
    ;
in
{
  sig = "Permission";
  doc = ''
    Bind mounts the runtime working directory as read-write.
  '';
  impl = include-once "mount-cwd" (unsafe-add-raw-args "--bind \"$PWD\" \"$PWD\"");
}
