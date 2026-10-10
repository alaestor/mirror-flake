{ profiles }:
{
  orchestration = profiles.orchestration + ''

    Select a registered role with spawn_agent's agent_type argument. Spawn reviewers
    with fork_turns="none" and only a self-contained objective, requirements,
    relevant constraints, and the location of the changes. Do not pass the primary
    or implementing agent's reasoning or conclusions. Default other roles to
    fork_turns="none" as well. Omit model and reasoning_effort overrides so the
    selected role's configured preset applies. If role selection is unavailable,
    report that limitation rather than substituting an unconfigured worker.
  '';

  roles = builtins.mapAttrs (name: model: {
    inherit model;
    model_reasoning_effort = "medium";
    inherit (profiles.roles.${name}) description;
    developer_instructions = profiles.worker + "\n" + profiles.roles.${name}.instructions;
  }) {
    fact-finder = "gpt-6-luna";
    mechanical-implementer = "gpt-6-luna";
    complex-implementer = "gpt-6.1-sol";
    reviewer = "gpt-6.1-sol";
  };
}
