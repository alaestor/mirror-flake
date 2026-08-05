/**
  Composes the interactive terminal environment and packages every direct
  `data/features/standard-terminal/scripts/*.nix` declaration. Each script
  file must return a package whose name matches its filename.
*/
{ inputs, self, ... }:
{
  flake.modules.homeManager.standard-terminal =
    { config, lib, pkgs, ... }:
    let

      # automatic discovery of scripts
      nixpkgsAllowUnfree = if pkgs.config.allowUnfree or false then "1" else "0";
      scriptDirectory = self.data.path "features/standard-terminal/scripts";
      scriptPackages = lib.mapAttrsToList (
        fileName: _:
        let
          expectedName = lib.removeSuffix ".nix" fileName;
          package = import "${scriptDirectory}/${fileName}" {
            inherit inputs nixpkgsAllowUnfree pkgs;
          };
        in
        if package.name != expectedName then
          throw "standard-terminal script ${fileName} declares the mismatched name ${package.name}"
        else
          package
      ) (lib.filterAttrs (fileName: fileType: fileType == "regular" && lib.hasSuffix ".nix" fileName) (
        builtins.readDir scriptDirectory
      ));

      # processed "uwu" themed fastfetch config (inserts ascii art)
      customLogoPath = self.data.vars.textart.boykisser;
      fastfetchUwuSettingsPath = pkgs.writeText "fastfetch-uwu.json" (
        builtins.replaceStrings [ "__NIX_REPLACED_LOGO_PATH__" ] [ (toString customLogoPath) ] (
          self.data.read "features/standard-terminal/fastfetch_uwu.json"
        )
      );

    in
    {
      home.packages = scriptPackages;

      imports = with inputs.self.modules.homeManager; [
        ghostty
        nushell
      ];

      programs = {
        ghostty.settings = {
          command = lib.mkDefault "nu";
          working-directory = lib.mkDefault config.home.homeDirectory;
        };

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
