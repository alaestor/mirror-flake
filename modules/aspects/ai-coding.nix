/**
  Bundles the Claude Code, Codex, and DeepSeek Harness agent modules for a
  user environment.
*/
{ inputs, ... }:
{
  flake.modules.homeManager.ai-coding =
    { pkgs, ... }:
    {
      imports = with inputs.self.modules.homeManager; [
        claude-code
        codex
        deepseek-harness
      ];

      home.packages = [ pkgs.herdr ];
    };
}
