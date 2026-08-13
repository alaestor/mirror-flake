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
