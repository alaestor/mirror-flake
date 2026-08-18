# (Originally from sourcehut:~alexdavid/jail.nix/404e7da9da5ab9aa643666682b2ba1312fa5fbe8 GPL-3.0)
{ helpers, ... }:
{
  sig = "String -> String -> Permission";
  doc = ''
    Sets the specified environment variable in the jail.

    This will throw if the variable name is not a valid posix variable name.
  '';
  impl =
    name: value: state:
    state
    // {
      env = state.env // {
        ${name} = helpers.escape value;
      };
    };
}
