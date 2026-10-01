/**
  Bundles the Claude Code, Codex, and DeepSeek Harness agent modules for a
  user environment.
*/
{ inputs, ... }:
{
  flake.modules.homeManager.ai-coding =
    { lib, pkgs, ... }:
    {
      imports = with inputs.self.modules.homeManager; [
        claude-code
        codex
        deepseek-harness
      ];

      # WORKAROUND: Once nixpkgs#568618 reaches nixos-unstable, remove this override and use pkgs.herdr directly.
      home.packages = [
        (pkgs.herdr.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
            substituteInPlace vendor/libghostty-vt/src/build/GhosttyLibVt.zig \
              --replace-fail 'lib.bundle_compiler_rt = true;' 'lib.bundle_compiler_rt = false;' \
              --replace-fail 'lib.bundle_ubsan_rt = true;' 'lib.bundle_ubsan_rt = false;'
          '';
        }))
      ];
    };
}
