/** Nushell, this author's default interactive shell. */
{ self, ... }:
{
  flake.modules.homeManager.nushell =
    {
      config,
      lib,
      options,
      pkgs,
      ...
    }:
    let
      shortcuts = self.data.read "programs/nushell/shortcuts.nu";
      passwordHelper = builtins.replaceStrings [ "@DICEWARE@" ] [ (lib.getExe pkgs.diceware) ] (
        self.data.read "programs/nushell/diceware-helper.nu"
      );
    in
    {
      home.packages = with pkgs; [
        #(aspellWithDicts (d: [d.en d.en-science]))
        bubblewrap
      ];

      programs.nushell = {
        enable = lib.mkDefault true;
        environmentVariables = config.home.sessionVariables;
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
          #a = lib.mkDefault "spell-check";
        };
        extraConfig = lib.mkAfter ''
          ${shortcuts}
          ${self.data.read "programs/nushell/fish-protocol.nu"}
          ${passwordHelper}
        '';
      } // lib.optionalAttrs (options.programs.nushell ? loadSessionVariables) {
        loadSessionVariables = lib.mkDefault true;
      };
    };
}
