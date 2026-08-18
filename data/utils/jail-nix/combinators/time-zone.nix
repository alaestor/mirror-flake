# (Originally from sourcehut:~alexdavid/jail.nix/404e7da9da5ab9aa643666682b2ba1312fa5fbe8 GPL-3.0)
{ combinators, ... }:
let
  inherit (combinators)
    add-runtime
    include-once
    ;
in
{
  sig = "Permission";
  doc = ''
    Exposes your timezone.
  '';
  impl = include-once "time-zone" (add-runtime ''
    if [ -L /etc/localtime ]; then
      RUNTIME_ARGS+=(
        --ro-bind "$(realpath /etc/localtime)" "$(readlink /etc/localtime)"
        --symlink "$(readlink /etc/localtime)" /etc/localtime
      )
    fi
  '');
}
