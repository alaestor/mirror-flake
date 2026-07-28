/**
  Local Jellyfin media service without public ingress policy.
*/
{
  flake.modules.nixos.serve-jellyfin =
    { config, lib, pkgs, ... }:
    let
      cfg = config.serve.jellyfin;
    in
    {
      options.serve.jellyfin = {
        user = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default =
            if config ? hostIdentity then
              config.hostIdentity.primaryUser
            else
              "jellyfin";
          defaultText = lib.literalExpression ''
            config.hostIdentity.primaryUser or "jellyfin"
          '';
          description = "Account under which Jellyfin runs.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8096;
          description = "Local Jellyfin HTTP port configured through Jellyfin.";
        };
      };

      config = {
        environment.systemPackages = with pkgs; [
          jellyfin
          jellyfin-web
          jellyfin-ffmpeg
        ];

        services.jellyfin = {
          enable = true;
          openFirewall = false;
          user = cfg.user;
        };
      };
    };
}
