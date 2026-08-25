/**
  Reusable Tailscale client feature with neutral connection defaults.

  Automatic enrollment still requires services.tailscale.authKeyFile; without
  one, use `tailscale up --login-server <URL>` to authenticate interactively.

  Attached user environments receive `standard-terminal.tailscale.domain`
  through the dormant `standard-terminal-tailnet` option interface.

*/
{ inputs, ... }:
{
  flake.modules.nixos.tailscale =
    { config, lib, ... }:
    let
      cfg = config.tailscale;
      homeModule =
        { lib, ... }:
        {
          # The interface may arrive through both this feature and a
          # contributing home environment feature.
          key = "flake.modules.nixos.tailscale#homeModule";

          imports = [ inputs.self.modules.homeManager.standard-terminal-tailnet ];

          standard-terminal.tailscale.domain = lib.mkDefault cfg.tailnetDomain;
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
