/**
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

  A check should identify a regression in repository behavior: a refused
  unsafe operation, a generated artifact, or an integration contract. Prefer
  synthetic identities and caller-supplied values over snapshots of personal
  configuration. Exercise both sides of a conditional; a disabled-only test
  also passes if the implementation does nothing. Do not test upstream merge
  semantics or grep implementation source as a substitute for running it.

  `nix flake check --no-build` evaluates checks but does not execute their
  builders. Use `nix build .#checks.<system>.<name> --no-link` for a focused
  test, or `nix flake check` to build the current system's full check set.
*/
{ inputs, self, ... }:
let
  testDirectory = "${self}/tests";

  testFiles = lib: lib.filterAttrs (
    fileName: fileType: fileType == "regular" && lib.hasSuffix ".nix" fileName
  ) (builtins.readDir testDirectory);
in
{
  perSystem =
    { lib, pkgs, system, ... }:
    {
      checks = lib.mapAttrs' (
        fileName: _:
        lib.nameValuePair (lib.removeSuffix ".nix" fileName) (
          import "${testDirectory}/${fileName}" { inherit inputs pkgs system; }
        )
      ) (testFiles lib);
    };
}
