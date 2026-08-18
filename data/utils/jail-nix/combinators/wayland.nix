# (Originally from sourcehut:~alexdavid/jail.nix/404e7da9da5ab9aa643666682b2ba1312fa5fbe8 GPL-3.0)
{ combinators, ... }:
let
  inherit (combinators)
    compose
    fwd-env
    noescape
    readonly
    ;
in
{
  sig = "Permission";
  doc = ''
    Exposes your wayland compositor to the jail.
  '';
  impl = compose [
    (fwd-env "WAYLAND_DISPLAY")
    (fwd-env "XDG_RUNTIME_DIR")
    (fwd-env "XDG_SESSION_TYPE")
    (readonly (noescape "\"$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY\""))
  ];
}
