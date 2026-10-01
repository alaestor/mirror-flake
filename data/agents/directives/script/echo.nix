{ pkgs, ... }:
{
  description = "Echo text on both both standard out and error";
  command = pkgs.writeShellApplication {
    name = "agent-directive-echo";
    text = ''
      printf '%s\n' "$*" | tee /dev/stderr
    '';
  };
}
