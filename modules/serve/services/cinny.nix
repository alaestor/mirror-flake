/**
  Cinny web artifact restricted to a configured Matrix homeserver.
*/
{ self, ... }:
{
  flake.modules.nixos.serve-cinny =
    { config, lib, pkgs, ... }:
    let
      cfg = config.serve.cinny;
    in
    {
      options.serve.cinny = {
        enable = lib.mkEnableOption "the configured Cinny web client artifact";

        homeserver = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = "Homeserver exposed by the customized Cinny build.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          description = "Cinny package containing the configured homeserver policy.";
        };
      };

      config = lib.mkIf cfg.enable {
        serve.cinny.package = pkgs.cinny.overrideAttrs (_: {
          installPhase = ''
            runHook preInstall
            cp -r dist $out
            substitute ${self.data.path "serve/cinny/config.json"} $out/config.json \
              --replace-fail '@HOMESERVER@' '${cfg.homeserver}'
            runHook postInstall
          '';
        });
      };
    };
}
