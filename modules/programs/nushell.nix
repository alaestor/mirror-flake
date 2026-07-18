{ inputs, self, ... }:
{
  flake.modules.homeManager.nushell =
    { lib, pkgs, ... }:
    let
      shortcuts = builtins.replaceStrings [ "@CURRENT_FLAKE@" ] [ (toString inputs.self) ] (
        self.data.read "programs/nushell/shortcuts.nu"
      );
      passwordHelper = builtins.replaceStrings [ "@DICEWARE@" ] [ (lib.getExe pkgs.diceware) ] (
        self.data.read "programs/nushell/password.nu"
      );
    in
    {
      home.packages = [ pkgs.aspell ];

      programs.nushell = {
        enable = lib.mkDefault true;
        settings = {
          show_banner = lib.mkDefault false;
          completions = {
            case_sensitive = lib.mkDefault false;
            quick = lib.mkDefault true;
            partial = lib.mkDefault true;
            algorithm = lib.mkDefault "fuzzy";
            external = {
              enable = lib.mkDefault true;
              max_results = lib.mkDefault 100;
            };
          };
        };
        shellAliases = {
          ll = lib.mkDefault "ls -la";
          lsrm = lib.mkDefault "lsblkrm";
          a = lib.mkDefault "spell-check";
        };
        extraConfig = lib.mkAfter ''
          ${shortcuts}
          ${self.data.read "programs/nushell/fish-protocol.nu"}
          ${passwordHelper}
        '';
      };
    };
}
