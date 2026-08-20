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
