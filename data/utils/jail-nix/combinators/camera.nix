# (Originally from sourcehut:~alexdavid/jail.nix/404e7da9da5ab9aa643666682b2ba1312fa5fbe8 GPL-3.0)
{ combinators, ... }:
let
  inherit (combinators) add-runtime include-once;
in
{
  sig = "Permission";
  doc = ''
    Allows access to webcams and other V4L2 video devices at `/dev/video*`.
  '';
  impl = include-once "camera" (add-runtime ''
    for v in /dev/video*; do
      [ -e "$v" ] || continue
      RUNTIME_ARGS+=(--dev-bind "$v" "$v")
    done
  '');
}
