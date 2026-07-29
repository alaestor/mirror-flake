{
  flake.nixOnDroidModules.base =
    { pkgs, ... }:
    {
      environment = {
        etcBackupExtension = ".bak";
        packages = with pkgs; [
          git
          neovim
          openssh
          ripgrep
        ];
      };

      nix.extraOptions = ''
        experimental-features = nix-command flakes
      '';

      system.stateVersion = "24.05";
    };
}
