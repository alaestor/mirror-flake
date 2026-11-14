{ isNixOnDroid, pkgs, ... }:
{
  name = "ngc";
  enable = true;
  package = pkgs.writeShellApplication {
    name = "ngc";
    text = ''
      exec ${pkgs.python3}/bin/python3 ${pkgs.replaceVars ../ngc.py {
        elevate = if isNixOnDroid then "" else "sudo";
      }} "$@"
    '';
  };
}
