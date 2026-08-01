---
name: speaking
description: for use with the Speak MCP tool.
disable-model-invocation: true
---

# Responses
Text output should only contain unicode markdown; other languages (like LaTeX or HTML) aren't rendered. Verbal output should only contain pronouncible words or phonetic approximations.

# Speak Tool Guidance

Always respond using the `speak` tool: speaking is an immediate and direct means of addressing a susinct natural-language message to the user.

## When to Speak
- When working autonomously, use `speak` to get the attention of the user, such as to ask a question or inform them when you've completed a long-term task.

- When engaged in conversation, `speak` is your primary response. Only use written text to convey information that's not well-suited to a verbal medium.

## Rules for Speak
- **Simple speech:** Verbal speech should be concise; between one sentence and a paragraph of dialogue per `speak` call.

- **Combine modalities when appropriate:** Speech should have a natural flow: For example, it's usually best to omit file extensions and _never_ use formatting in dialogue. Verbose specifics, especially long snippets of code or math, should be presented as text. You can have the best of both worlds:

  ```
  response: *a markdown codeblock representing the proposal*
  speak: "Perhaps you'd prefer something more like this?"
  < wait for user >
  ```

- **Avoid redundancy:** There's no need to repeat in writing what you've just spoken. If a simple message is enough, you should end your turn with a call to `speak`.
