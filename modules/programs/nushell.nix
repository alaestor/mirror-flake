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
      hasNasVault = lib.hasAttrByPath [ "hostContext" "nas" "vaultMountpoint" ] options;
      shortcuts = self.data.read "programs/nushell/shortcuts.nu";
      passwordHelper = builtins.replaceStrings [ "@DICEWARE@" ] [ (lib.getExe pkgs.diceware) ] (
        self.data.read "programs/nushell/diceware-helper.nu"
      );
      flakeHelper =
        if !hasNasVault then
          ""
        else
          builtins.replaceStrings
            [ "@LOCAL_FLAKE@" ]
            [ "${config.hostContext.nas.vaultMountpoint}/.dotfiles/flake" ]
            (self.data.read "programs/nushell/flake-helpers.nu");
    in
    {
      home.packages = with pkgs; [
        (aspellWithDicts (d: [d.en d.en-computers d.en-science]))
      ];

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
          ${flakeHelper}
        '';
      };
    };
}
