# (Originally from sourcehut:~alexdavid/jail.nix/404e7da9da5ab9aa643666682b2ba1312fa5fbe8 GPL-3.0)
{ ... }:
{
  sig = "String -> Permission";
  doc = ''
    Sets the hostname to use for the `network` combinator.

    Must be specified before `network`.

    Example:
    ```nix
    [
      (set-hostname "foo")
      network
    ]
    ```
  '';
  impl = hostname: state: state // { inherit hostname; };
}
