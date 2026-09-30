{ pkgs }:
# A directive command receives one raw argument string and writes optional
# context to stdout. It may change files in the caller's working directory.
{
  pickup = {
    description = "Read the latest handoff into this turn";
    command = pkgs.writeShellApplication {
      name = "agent-directive-pickup";
      runtimeInputs = with pkgs; [ coreutils ];
      text = builtins.readFile ./pickup.sh;
    };
  };
}
