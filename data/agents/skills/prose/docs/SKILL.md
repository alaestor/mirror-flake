---
name: docs
description: Use when writing documentation files (generalized docs only, not ADR or spec)
---

Documentation should be durable onboarding material written in github-flavored markdown; it shouldn't catalogue implementation details or broadly index source files without very good reason (in such rare cases, the files should crosslink back to documentation via comments to inform authors to keep them in-sync).

Documents contain meaningful and valuable information that isn't immediately apparent from glancing at the repo. Statements should be sussinct and use an active voice. Illustrations are encouraged, but only when they meaningfully illucidate information; e.g. a hierarchy of three items is better explained in a single text line as `inheritance: x -> y -> z` rather than a giant mermaid diagram.

Prose should be concise and direct, resolving ambiguities as they arise, and be as self-contained as reasonably possible. They should use domain-specific language where appropriate, and remain consistent with any CONTEXT.md or glossary where available. Relative file links can be used to direct users to supplementary or reference information. Invoke the `unslop` prose skill if available.
