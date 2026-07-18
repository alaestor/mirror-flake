{ inputs, self, ... }:
{
  flake.modules.homeManager.standard-terminal =
    { lib, pkgs, ... }:
    let
      customLogoPath = self.data.vars.textart.boykisser;
      fastfetchUwuSettingsPath = pkgs.writeText "fastfetch-uwu.json" (
        builtins.replaceStrings [ "__NIX_REPLACED_LOGO_PATH__" ] [ (toString customLogoPath) ] (
          self.data.read "features/standard-terminal/fastfetch_uwu.json"
        )
      );
    in
    {
      imports = with inputs.self.modules.homeManager; [
        ghostty
        nushell
      ];

      programs = {
        ghostty.settings.command = lib.mkDefault "nu";

        fastfetch = {
          enable = lib.mkDefault true;
          settings = self.data.readJSON "features/standard-terminal/fastfetch.json";
        };

        hyfetch = {
          enable = lib.mkDefault true;
          settings = {
            backend = lib.mkDefault "fastfetch";
            mode = lib.mkDefault "rgb";
            preset = lib.mkDefault "random";
            light_dark = lib.mkDefault "dark";
            pride_month_disable = lib.mkDefault true;
            color_align.mode = lib.mkDefault "horizontal";
          };
        };

        carapace = {
          enable = lib.mkDefault true;
          enableNushellIntegration = lib.mkDefault true;
        };

        starship = {
          enable = lib.mkDefault true;
          enableNushellIntegration = lib.mkDefault true;
          settings = {
            add_newline = lib.mkDefault true;
            character = {
              success_symbol = lib.mkDefault "[λ](bold green)";
              error_symbol = lib.mkDefault "[✗](bold red)";
            };
          };
        };

        zoxide = {
          enable = lib.mkDefault true;
          enableNushellIntegration = lib.mkDefault true;
        };

        atuin = {
          enable = lib.mkDefault true;
          enableNushellIntegration = lib.mkDefault true;
        };

        nushell.extraConfig = lib.mkAfter ''
          def --wrapped ff [...args] {
            fastfetch ...$args
          }

          def --wrapped ffuwu [...args] {
            fastfetch -c ${fastfetchUwuSettingsPath} ...$args
          }

          def --wrapped hy [...args] {
            hyfetch ...$args
          }

          def --wrapped hyuwu [...args] {
            hyfetch --ascii-file ${customLogoPath} ...$args --args "-c ${fastfetchUwuSettingsPath}"
          }

          clear
        '';
      };
    };
}
