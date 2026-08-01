/**
  Tailscale client defaults for hosts joining this flake's Headscale network.

  Automatic enrollment still requires services.tailscale.authKeyFile; without
  one, use `tailscale up --login-server <URL>` to authenticate interactively.
*/
{ config, ... }:
let
  headscaleHostName = "lanser";
  headscaleServerUrl =
    config.flake.nixosConfigurations.${headscaleHostName}.config.services.headscale.settings.server_url;
in
{
  flake.modules.nixos.tailscale =
    { config, lib, ... }:
    let
      cfg = config.tailscale;
      defaultLoginServer =
        if config.networking.hostName == headscaleHostName then null else headscaleServerUrl;
    in
    {
      options.tailscale = {
        enable = lib.mkEnableOption "the Tailscale client";

        loginServer = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = defaultLoginServer;
          defaultText = lib.literalExpression ''
            config.flake.nixosConfigurations.${headscaleHostName}.config.services.headscale.settings.server_url
          '';
          description = ''
            Headscale coordination-server URL used when enrolling with
            services.tailscale.authKeyFile. Set to null to use Tailscale's
            hosted coordination server instead.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        services.tailscale = {
          enable = true;
          openFirewall = lib.mkDefault true;
          extraUpFlags = lib.mkDefault (
            lib.optional (cfg.loginServer != null) "--login-server=${cfg.loginServer}"
          );
        };
      };
    };
}
