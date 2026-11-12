## mkstatus

Generates a self-contained repository status report from scoped TODO,
warning, and note comments, grouped and filtered by marker, scope, or
directory.

Ignores README files, case-insensitively, to avoid counting annotations
copied into generated documentation.

Run from the flake root with `nix run .#mkstatus`.
