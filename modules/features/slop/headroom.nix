/**
  User service for the Headroom context-compression proxy that agent CLIs
  sit behind.
*/
{ inputs, ... }:
{
  flake.modules.homeManager.headroom =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.headroom-proxy;
      defaultPackage = inputs.alpkgs.packages.${pkgs.stdenv.hostPlatform.system}.headroom;
    in
    {
      options.services.headroom-proxy = {
        enable = lib.mkEnableOption "the Headroom user proxy service";

        package = lib.mkOption {
          type = lib.types.package;
          default = defaultPackage;
          defaultText = lib.literalExpression "inputs.alpkgs.packages.<system>.headroom";
          description = "Headroom package used by the proxy service.";
        };

        address = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "127.0.0.1";
          description = "Address on which the Headroom proxy listens.";
        };

        port = lib.mkOption {
          type = lib.types.ints.between 1 65535;
          default = 8787;
          description = "Port on which the Headroom proxy listens.";
        };

        shape-output = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether Headroom's output-token shaper is enabled.";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.user.services.headroom-proxy = {
          Unit.Description = "Headroom optimization proxy";

          Service = {
            Environment = "HEADROOM_OUTPUT_SHAPER=${if cfg.shape-output then "1" else "0"}";
            ExecStart = lib.escapeShellArgs [
              (lib.getExe cfg.package)
              "proxy"
              "--host"
              cfg.address
              "--port"
              (toString cfg.port)
            ];
            Restart = "on-failure";
            RestartSec = 2;
          };
        };
      };
    };
}
