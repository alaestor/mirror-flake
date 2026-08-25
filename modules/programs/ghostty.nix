/** Ghostty terminal emulator, enabled by default. */
{
  flake.modules.homeManager.ghostty =
    { lib, ... }:
    {
      programs.ghostty = {
        enable = lib.mkDefault true;
        clearDefaultKeybinds = lib.mkDefault false;
        settings = {
          confirm-close-surface = lib.mkDefault false;
          window-height = lib.mkDefault 24;
          window-width = lib.mkDefault 80;
        };
      };
    };
}
