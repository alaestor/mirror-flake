/**
  Headscale coordination server with the Headplane administrative interface.

  The services listen only on loopback by default. Hosts choose whether to
  enable the service and publish it through their reverse proxy.
*/
{ ... }:
{
  flake.modules.nixos.serve-headscale =
    { config, lib, pkgs, ... }:
    let
      cfg = config.serve.headscale;
      headscale = config.services.headscale;
      headplane = config.services.headplane;
      cookieSecretPath = "/var/lib/headplane/cookie-secret";
    in
    {
      options.serve.headscale = {
        enable = lib.mkEnableOption "the Headscale coordination server and Headplane administration interface";

        adminAllowedCIDRs = lib.mkOption {
          type = lib.types.listOf lib.types.nonEmptyStr;
          default = [ ];
          description = "Networks allowed to reach Headplane's /admin interface through a domain composition.";
          example = [
            "192.168.2.0/23"
            "100.64.0.0/10"
          ];
        };
      };

      config = lib.mkIf cfg.enable {
        services = {
          headscale = {
            enable = true;
            address = lib.mkDefault "127.0.0.1";
            port = lib.mkDefault 8092;
            settings.dns = {
              # A reusable service module cannot safely choose a MagicDNS suffix
              # or recursive resolvers. Hosts opt in with their own DNS policy.
              magic_dns = lib.mkDefault false;
              override_local_dns = lib.mkDefault false;
            };
          };

          headplane = {
            enable = true;
            settings = {
              server = {
                host = lib.mkDefault "127.0.0.1";
                port = lib.mkDefault 3000;
                cookie_secret_path = lib.mkDefault cookieSecretPath;
              };

              headscale = {
                url = lib.mkDefault "http://${headscale.address}:${toString headscale.port}";
                config_path = lib.mkDefault headscale.configFile;
              };
            };
          };
        };

        # TODO(secrets): agenix probably
        # Headplane requires a 32-character session-secret. Keep it outside the
        # Nix store and preserve it across service restarts and deployments.
        systemd.services.headplane = lib.mkIf headplane.enable {
          serviceConfig.UMask = "0077";
          preStart = lib.mkBefore ''
            if ! test -s ${lib.escapeShellArg cookieSecretPath}; then
              ${lib.getExe pkgs.openssl} rand -hex 16 | ${lib.getExe' pkgs.coreutils "head"} -c 32 > ${lib.escapeShellArg cookieSecretPath}
            fi
          '';
        };
      };
    };
}
