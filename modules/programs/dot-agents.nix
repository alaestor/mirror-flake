{ self, ... }:
{
  flake.modules.homeManager.dot-agents = {
    home.file = {
      ".agents/AGENTS.md".source = self.data.path "agents/AGENTS.md";
      ".agents/skills" = {
        source = self.data.path "agents/skills";
        recursive = true;
      };
    };
  };
}
