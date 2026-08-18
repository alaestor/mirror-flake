# (Originally from sourcehut:~alexdavid/jail.nix/404e7da9da5ab9aa643666682b2ba1312fa5fbe8 GPL-3.0)
{ combinators, ... }:
let
  inherit (combinators)
    compose
    fwd-env
    include-once
    unsafe-add-raw-args
    ;
in
{
  sig = "Permission";
  doc = ''
    Exposes pipewire to the jailed application.
  '';
  impl = include-once "pipewire" (compose [
    (fwd-env "XDG_RUNTIME_DIR")
    (unsafe-add-raw-args "--bind-try \"$XDG_RUNTIME_DIR/pipewire-0\" \"$XDG_RUNTIME_DIR/pipewire-0\"")
    (unsafe-add-raw-args "--bind-try /run/pipewire /run/pipewire")
  ]);
}
