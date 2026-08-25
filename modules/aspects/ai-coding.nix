/**
  Bundles the Claude Code and Codex agent modules for a user environment.
*/
{ inputs, ... }:
{
  flake.modules.homeManager.ai-coding =
    { pkgs, ... }:
    {
      imports = with inputs.self.modules.homeManager; [
        claude-code
        codex
      ];

      home.packages = [ pkgs.herdr ];
    };
}
