# Propose a durable fix

Repeated rediscovery or recurring workarounds may indicate missing documentation,
a tooling defect, or a harness problem. Inspect evidence rather than inferring a
problem from read counts alone. Identify the owning documentation or mechanism
and the smallest change that would remove the recurring obligation.

Use `memory propose <id> --proposal 'specific change and owner' --evidence 'observed recurrence'`.
Proposals appear in `memory promotions` for human review. Recording a proposal
is not authority to change prompts, policy, or tools. After an approved fix,
verify it, close the proposal with `memory promotion-close <id> --note 'result'`,
and consider deleting the now-redundant article.
