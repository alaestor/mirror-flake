{ pkgs, ... }:
{
  name = "lola";
  enable = true;
  package = pkgs.writeShellApplication {
    name = "lola";
    runtimeInputs = [ pkgs.git ];
    text = ''
      exec git log --graph --decorate --pretty=oneline --abbrev-commit --all "$@"
    '';
  };
}
