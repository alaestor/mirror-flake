## checks

Wires every top-level `tests/*.nix` file into `perSystem.checks` under its
basename. Each test file is a function taking `{ inputs, pkgs, system }` and
returning a derivation that fails the build when its assertions fail.

Discovery is by `builtins.readDir` over the flake source, so a new test needs
no wiring module, but an untracked test file is invisible to a flake
evaluation until it is staged. Directories under `tests/` are skipped, which
keeps shared harnesses such as `tests/lib/` and fixtures such as
`tests/jellybuilder/` out of the check set; those are imported by the tests
that use them, or wired by the module they exercise.

This is not the only source of `perSystem.checks`: modules may also
contribute a check directly, colocated with the thing it tests
(`modules/utils/mkstatus/mkstatus.nix`,
`modules/features/nix-store-signing.nix`). The full check set is the union
of both mechanisms, not just what's under `tests/`.
