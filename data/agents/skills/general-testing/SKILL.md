---
name: general-testing
description: Comprehensive Testing - A Short Guide To Writing Good Tests
disable-model-invocation: false
---

# Comprehensive Testing Requirements -- How to Write Good Tests

Think in terms of API specification and the guarentees it's making. Ambiguity should be considered a defect.

- Tests should be clear and concise with a Given-When-Then structure.
- Tests should succeed with minimal verbosity, but loudly fail hard and fast.
- Unit test cases should try to isolate and validate as small of a surface area as possible.
- Integration test cases should encompass a high-level workflows to validate how components fit together. It's also important to simulate component failures at various steps along the chain.
- Test for both positive and negative cases to guarentee the expected behavior under a variety of conditions.
- Test the interface and its guarentees, not the underlying implementation.
