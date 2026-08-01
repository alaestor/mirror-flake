---
name: subagents-local-sequential
description: How to use subagents efficienty when running on a resource-confined single-model local backend.
disable-model-invocation: true
---

- Only run sequential agents: spawning only one at a time (parallelism isn't supported by the backend).
- Always use agents for tasks that require reading and writing from many files.
- You're encouraged to use agents when problem-solving or answering elaborate questions that may require experimentation, deep project exploration, or lengthy reasoning.

Using agents is critical to maintaining high-fidelity context and efficiently utilizing your limited memory. Carefully consider what information the subagent needs to do its job, and what information you need back from it.
