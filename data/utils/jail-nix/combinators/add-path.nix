# (Originally from sourcehut:~alexdavid/jail.nix/404e7da9da5ab9aa643666682b2ba1312fa5fbe8 GPL-3.0)
{ ... }:
{
  sig = "String -> Permission";
  doc = ''
    Prepends the passed string to `$PATH`.
  '';
  impl =
    path: state:
    state
    // {
      env = state.env // {
        PATH = if state.env ? PATH && state.env.PATH != "" then "${path}:${state.env.PATH}" else path;
      };
    };
}
