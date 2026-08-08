/**
  Reusable Tailscale client feature with neutral connection defaults.

  Automatic enrollment still requires services.tailscale.authKeyFile; without
  one, use `tailscale up --login-server <URL>` to authenticate interactively.

*/
{ ... }:
{
  flake.modules.nixos.tailscale =
    { config, lib, options, ... }:
    let
      cfg = config.tailscale;
      homeModule =
        { lib, options, ... }:
        {
          config = lib.mkIf (options ? standard-terminal) {
            standard-terminal.tailscale.domain = lib.mkDefault cfg.tailnetDomain;
          };
        };
    in
    {
      options.tailscale = {
        enable = lib.mkEnableOption "the Tailscale client";

        loginServer = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Headscale coordination-server URL used when enrolling with
            services.tailscale.authKeyFile. Set to null to use Tailscale's
            hosted coordination server instead.
          '';
        };

        tailnetDomain = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Tailnet DNS suffix used by terminal shortcuts.";
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

        userEnvironment.sharedModules = [ homeModule ];
      };
    };

}
