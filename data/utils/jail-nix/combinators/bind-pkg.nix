# (Originally from sourcehut:~alexdavid/jail.nix/404e7da9da5ab9aa643666682b2ba1312fa5fbe8 GPL-3.0)
{ combinators, helpers, ... }:
let
  inherit (combinators) compose ro-bind;
in
{
  sig = "String -> Package -> Permission";
  doc = ''
    Bind mounts the passed derivation at a specified location.

    Example:
    ```nix
    bind-pkg "/foo" (pkgs.writeText "foo" "bar")
    ```
  '';
  impl =
    path: pkg:
    compose [
      (ro-bind (toString pkg) path)
      (helpers.pushState "additionalRuntimeClosures" pkg)
    ];
}
