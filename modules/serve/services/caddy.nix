/**
  Shared Caddy instance built with the Cerberus challenge plugin.
*/
{
  flake.modules.nixos.serve-caddy =
    { config, lib, pkgs, ... }:
    let
      cfg = config.serve.caddy;
    in
    {
      options.serve.caddy = {
        enable = lib.mkEnableOption "the shared Caddy reverse proxy";

        bindAddress = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = "Address used by Caddy's default_bind global option.";
        };

        contact = lib.mkOption {
          type = lib.types.str;
          # INTENTIONAL: literal placeholder, not a real address. This text is
          # generic on purpose so it stays true regardless of which domain
          # (0x04.cc, bokunopi.co, ...) a given visitor landed on; per-domain
          # composition modules could override it with a real address per
          # domain if that's ever wanted, but nothing does today.
          default = "admin @ this domain";
          description = "Contact text displayed by the Cerberus challenge page.";
        };
      };

      config = lib.mkIf cfg.enable {
        services.caddy = {
          enable = true;
          package = pkgs.caddy.withPlugins {
            plugins = [ "github.com/sjtug/cerberus@v0.4.6" ];
            hash = "sha256-l5qBSMBn7SQKv0N+KrT2vnTejSgOwY2HsrX6v4jKcm4=";
          };
          dataDir = "/var/lib/caddy";
          # The nixpkgs module emits its own global `log` block from this
          # option; declaring another one in globalConfig is a parse error.
          logFormat = ''
            output stdout
            format json
          '';
          globalConfig = ''
            default_bind ${cfg.bindAddress}
            cerberus {
              difficulty 12
              max_pending 512
              access_per_approval 200
              block_ttl "1h"
              pending_ttl "10m"
              approval_ttl "168h"
              max_mem_usage "512MiB"
              cookie_name "cerberus-auth"
              header_name "X-Cerberus-Status"
              title "Cerberus Challenge"
              mail "${cfg.contact}"
            }
            key_type rsa4096
          '';
        };
      };
    };
}
