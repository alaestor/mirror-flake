{ pkgs, ... }:
{
  name = "pw";
  enable = true;
  package = pkgs.writeShellApplication {
    name = "pw";
    runtimeInputs = [ pkgs.coreutils pkgs.diceware ];
    text = builtins.readFile ./pw.sh;
  };
}
