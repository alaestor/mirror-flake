---
name: nix-flake-pattern-normal-flakes
description: Guidance for writing minimal Nix flakes. (DEPRECATED)
license: MIT
disable-model-invocation: true
---

Use as few third-party inputs as possible in a conventional Nix flake unless otherwise instructed. Use helper functions and `let` bindings to centralize user-facing configuration and reduce duplication. Prioritize readability and maintainability unless instructed otherwise.
