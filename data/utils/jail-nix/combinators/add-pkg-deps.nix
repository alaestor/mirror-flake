# (Originally from sourcehut:~alexdavid/jail.nix/404e7da9da5ab9aa643666682b2ba1312fa5fbe8 GPL-3.0)
{ combinators, lib, ... }:
let
  inherit (combinators) compose add-path;
in
{
  sig = "[Package] -> Permission";
  doc = ''
    Adds the packages' `bin` directory to `$PATH`.
  '';
  impl =
    pkgsToAdd:
    compose (
      builtins.map (pkg: add-path "${lib.getBin pkg}/bin") pkgsToAdd
      ++ [
        (
          state:
          state
          // {
            additionalRuntimeClosures = state.additionalRuntimeClosures ++ (map toString pkgsToAdd);
          }
        )
      ]
    );
}
