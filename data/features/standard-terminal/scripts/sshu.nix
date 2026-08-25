{ pkgs, ... }:
{
  name = "sshu";
  enable = true;
  package = pkgs.writeShellApplication {
    name = "sshu";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      # Deliberately bypass host-key verification for an ad-hoc connection.
      exec ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" "$@"
    '';
  };
}
