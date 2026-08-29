/** VSCodium with Cheat Engine Auto Assembler support, enabled by default. */
{ inputs, ... }:
{
  flake.modules.homeManager.vscodium =
    { lib, pkgs, ... }:
    let
      cea = inputs.zed-cea.packages.${pkgs.stdenv.hostPlatform.system};
    in
    {
      # `programs.vscode` with `package = pkgs.vscodium` still writes to Visual
      # Studio Code's own paths; the dedicated module targets VSCodium's.
      programs.vscodium = {
        enable = lib.mkDefault true;
        mutableExtensionsDir = lib.mkDefault false;

        profiles.default = {
          extensions = [
            cea.vscode-cea
          ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
            {
              publisher = "icsharpcode";
              name = "ilspy-vscode";
              version = "0.2.0";
              sha256 = "sha256-LHyndMe7SCf7j5jvOWUwAMzPknenGoaDAADHH25Pc24=";
            }
            {
              publisher = "stivo";
              name = "tailwind-fold";
              version = "0.2.0";
              sha256 = "sha256-yH3eA5jgBwxqnpFQkg91KQMkQps5iM1v783KQkQcWUU=";
            }
            {
              publisher = "svelte";
              name = "svelte-vscode";
              version = "110.3.1";
              sha256 = "sha256-C3lJ7MO6GTJIotBa71vQN/L6A8iWZ9viYNniT6I2DMQ=";
            }
            {
              publisher = "arrterian";
              name = "nix-env-selector";
              version = "1.3.2";
              sha256 = "sha256-bEvSaA1pUNmz7LCScsqE0SXVMtcF7PaXO4kuoZyIryg=";
            }
            {
              publisher = "golang";
              name = "go";
              version = "0.46.1";
              sha256 = "sha256-R5SC6vMWT3alunlklJKcEKKJhNd6GI2MF9/QWwuNprs=";
            }
            {
              publisher = "manuth";
              name = "eslint-language-service";
              version = "1.1.3";
              sha256 = "sha256-0edURVf66DhBkcg1C0Xa/1jEvo0HWE2j5hffR0Xlic4=";
            }
            {
              publisher = "vscodevim";
              name = "vim";
              version = "1.32.4";
              sha256 = "sha256-+hyJZinWsa6U+s0fdrx2wUi6tOV3FNKf8O1qMMZEdkQ=";
            }
          ];

          userSettings = {
            # The client resolves both executables from PATH by default, which a
            # GUI launch does not inherit; point at the store instead.
            "cea.server.path" = "${cea.cea-language-server}/bin/cea-language-server";
            "cea.luaLanguageServer.path" = lib.getExe pkgs.lua-language-server;

            "telemetry.telemetryLevel" = lib.mkDefault "off";
            "update.mode" = lib.mkDefault "none";
            "extensions.autoUpdate" = lib.mkDefault false;
          };
        };
      };
    };
}
