---
name: subagents-manual
description: Don't use the subagent tooling; do this instead.
disable-model-invocation: true
---

Instead of using the subagent tooling, interact with the user and ask them to create a subagent: provide them a prompt to use, like you would prompt the tool.

They will spawn another fully-featured thread and mashall I/O between you as needed. This helps manage the context window, and also allows the user to directly engage with the subagent if needed (which is a limitation of traditional subagents)
