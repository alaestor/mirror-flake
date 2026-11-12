## agent-find-guard

Exercises `flake.lib.agents.findGuardBashEnv` (`modules/mechanisms/libagents/libagents.nix`)
against a synthetic exported shell function. Checks root refusal and
delegation, including preservation of an existing wrapper. It does not
establish compatibility with every version of Claude Code's shell setup.
