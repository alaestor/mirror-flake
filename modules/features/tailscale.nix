/**
  Tailscale client defaults for hosts joining this flake's Headscale network.

  Automatic enrollment still requires services.tailscale.authKeyFile; without
  one, use `tailscale up --login-server <URL>` to authenticate interactively.

  The Nix-on-Droid attachment does not install or enable Tailscale. Android's
  host OS is expected to run the Tailscale application and own the VPN; the
  attachment only selects its DNS resolver and enables terminal shortcuts.
*/
{ config, inputs, ... }:
let
  headscaleHostName = "lanser";
  headscaleServerUrl =
    config.flake.nixosConfigurations.${headscaleHostName}.config.services.headscale.settings.server_url;
  headscaleTailnetDomain =
    config.flake.nixosConfigurations.${headscaleHostName}.config.services.headscale.settings.dns.base_domain;
in
{
  flake.modules.nixos.tailscale =
    { config, lib, options, ... }:
    let
      cfg = config.tailscale;
      defaultLoginServer =
        if config.networking.hostName == headscaleHostName then null else headscaleServerUrl;
      tailnetDomain = headscaleTailnetDomain;
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

        tailnetDomain = lib.mkOption {
          type = lib.types.str;
          default = tailnetDomain;
          defaultText = lib.literalExpression ''
            config.flake.nixosConfigurations.${headscaleHostName}.config.services.headscale.settings.dns.base_domain
          '';
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

  flake.nixOnDroidModules.tailscale =
    { lib, ... }:
    {
      imports = [ inputs.self.nixOnDroidModules.standard-terminal ];

      environment.etc."resolv.conf".text = lib.mkForce ''
        nameserver 100.100.100.100
      '';

      home-manager.config.standard-terminal.tailscale.domain = headscaleTailnetDomain;
    };
}
