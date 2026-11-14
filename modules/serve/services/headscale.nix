/**
  Headscale coordination server with the Headplane administrative interface.

  The services listen only on loopback by default. Hosts choose whether to
  enable the service and publish it through their reverse proxy.
  Headplane has its own account and state, with API-backed administration
  but no access to Headscale's private state or process-control integration.
*/
{ ... }:
{
  flake.modules.nixos.serve-headscale =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.serve.headscale;
      headscale = config.services.headscale;
      headplane = config.services.headplane;
      cookieSecretPath = "/var/lib/headplane/cookie-secret";
      externalCookieSecret = cfg.cookieSecretFile != cookieSecretPath;
    in
    {
      options.serve.headscale = {
        enable = lib.mkEnableOption "the Headscale coordination server and Headplane administration interface";

        cookieSecretFile = lib.mkOption {
          type = lib.types.str;
          default = cookieSecretPath;
          description = ''
            Runtime file containing Headplane's 32-character cookie secret.
            The default is generated persistently in its state directory.
            Custom paths must exist at startup and are read by systemd through
            LoadCredential, so their source can remain root-only.
          '';
        };

        adminAllowedCIDRs = lib.mkOption {
          type = lib.types.listOf lib.types.nonEmptyStr;
          default = [ ];
          description = "Networks allowed to reach Headplane's /admin interface through a domain composition.";
          example = [
            "10.20.0.0/24"
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
                cookie_secret_path = lib.mkDefault (
                  if externalCookieSecret then "/run/credentials/headplane.service/cookie-secret"
                  else cookieSecretPath
                );
              };

              headscale = {
                url = lib.mkDefault "http://${headscale.address}:${toString headscale.port}";
                config_path = lib.mkDefault headscale.configFile;
              };
              # Nix owns configuration changes. UI administration uses HTTP,
              # not permission to signal the coordinator's process.
              integration.proc.enabled = lib.mkDefault false;
            };
          };
        };

        users.groups.headplane = { };
        users.users.headplane = {
          isSystemUser = true;
          group = "headplane";
          home = headplane.settings.server.data_path;
          description = "Headplane administration interface";
        };

        systemd.services.headplane = lib.mkIf headplane.enable {
          # Generate only the local default. Never replace a missing managed
          # secret with a new random value or try to write into its directory.
          preStart = lib.mkIf (!externalCookieSecret) (lib.mkBefore ''
            if ! test -s ${lib.escapeShellArg cfg.cookieSecretFile}; then
              ${lib.getExe pkgs.openssl} rand -hex 16 | ${lib.getExe' pkgs.coreutils "head"} -c 32 > ${lib.escapeShellArg cfg.cookieSecretFile}
            fi
          '');
          serviceConfig = {
            # Deliberately replace nixpkgs' coupling to the Headscale account.
            User = lib.mkForce "headplane";
            Group = lib.mkForce "headplane";
            StateDirectoryMode = "0700";
            UMask = "0077";
            LoadCredential = lib.optional externalCookieSecret "cookie-secret:${cfg.cookieSecretFile}";
            ProtectSystem = lib.mkDefault "strict";
            ProtectHome = lib.mkDefault true;
            PrivateTmp = lib.mkDefault true;
            PrivateDevices = lib.mkDefault true;
            ReadWritePaths = [ headplane.settings.server.data_path ];
            ReadOnlyPaths = [ "/run" ];
            InaccessiblePaths = [ "/var/lib/headscale" "/run/headscale" ];
            NoNewPrivileges = lib.mkDefault true;
            CapabilityBoundingSet = lib.mkDefault "";
            AmbientCapabilities = lib.mkDefault "";
            ProtectKernelTunables = lib.mkDefault true;
            ProtectKernelModules = lib.mkDefault true;
            ProtectKernelLogs = lib.mkDefault true;
            ProtectControlGroups = lib.mkDefault true;
            ProtectClock = lib.mkDefault true;
            ProtectHostname = lib.mkDefault true;
            ProtectProc = lib.mkDefault "invisible";
            ProcSubset = lib.mkDefault "pid";
            RestrictNamespaces = lib.mkDefault true;
            RestrictSUIDSGID = lib.mkDefault true;
            RestrictRealtime = lib.mkDefault true;
            LockPersonality = lib.mkDefault true;
            SystemCallArchitectures = lib.mkDefault "native";
            SystemCallFilter = [ "@system-service" ];
            RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
            # Node's JIT needs executable memory; do not deny write/execute.
          };
        };
      };
    };
}
