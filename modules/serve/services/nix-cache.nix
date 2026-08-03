/**
  Private HTTP Nix binary cache backed by the host's Nix store.

  Exports `flake.modules.nixos.serve-nix-cache`. Importing it has no effect;
  `serve.nix-cache.enable` must be set explicitly. The listener is exposed only
  through the configured private firewall interface.
*/
{ inputs, self, ... }:

{
  flake.modules.nixos.serve-nix-cache =
    { config, lib, ... }:
    let
      cfg = config.serve.nix-cache;
      keyName = "${cfg.authority}-${toString cfg.rotation}";
      secret = self.secrets.nixStoreSigning keyName;
    in
    {
      imports = [ inputs.self.modules.nixos.nix-store-signing ];

      options.serve.nix-cache = {
        enable = lib.mkEnableOption "the private HTTP Nix binary cache";
        address = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = "Address on which nix-serve listens.";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 5000;
          description = "Port on which nix-serve listens.";
        };
        privateInterface = lib.mkOption {
          type = lib.types.str;
          default = "tailscale0";
          description = "Private interface allowed through the firewall.";
        };
        authority = lib.mkOption {
          type = lib.types.str;
          default = config.networking.fqdn;
          defaultText = lib.literalExpression "config.networking.fqdn";
          description = "DNS-like signing authority of this cache.";
        };
        rotation = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1;
          description = "Cache signing-key rotation counter.";
        };
      };

      config = lib.mkIf cfg.enable {
        nix-store-signing = {
          enable = true;
          authority = lib.mkDefault cfg.authority;
          rotation = lib.mkDefault cfg.rotation;
        };

        services.nix-serve = lib.mkIf secret.exists {
          enable = true;
          bindAddress = cfg.address;
          inherit (cfg) port;
          openFirewall = false;
          secretKeyFile = config.nix-store-signing.secretPath;
        };

        systemd.services.nix-serve = lib.mkIf secret.exists {
          after = [ "agenix.service" ];
        };

        networking.firewall.interfaces.${cfg.privateInterface}.allowedTCPPorts =
          lib.optional secret.exists cfg.port;
      };
    };
}
