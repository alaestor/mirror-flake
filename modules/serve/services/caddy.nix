/**
  Shared Caddy instance built with the Cerberus challenge plugin.

  The filesystem is read-only outside Caddy's state, logs, private runtime
  directory, and temporary storage. Hosts own additional storage boundaries.
  NixOS reloads use a private administrative Unix socket, not a TCP listener.
*/
{ self, ... }:
{
  flake.modules.nixos.serve-caddy =
    { config, lib, pkgs, ... }:
    let
      cfg = config.serve.caddy;
      adminSocket = "/run/caddy/admin.sock";
      ports = self.fleet.ports.shared;
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
            hash = (self.data.readJSON "serve/caddy/source.json").hash;
          };
          dataDir = "/var/lib/caddy";
          # The nixpkgs module emits its own global `log` block from this
          # option; declaring another one in globalConfig is a parse error.
          logFormat = ''
            output stdout
            format json
          '';
          globalConfig = ''
            admin unix/${adminSocket}|0600
            default_bind ${cfg.bindAddress}
            http_port ${toString ports.caddy-http}
            https_port ${toString ports.caddy-https}
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

        systemd.services.caddy.serviceConfig = {
          ProtectSystem = lib.mkDefault "strict";
          # nixpkgs already grants dataDir; retain configured file-log support.
          ReadWritePaths = [ config.services.caddy.logDir "/run/caddy" ];
          ReadOnlyPaths = [ "/run" ];
          # Only the service account and root can reach the reload API.
          RuntimeDirectory = [ "caddy" ];
          RuntimeDirectoryMode = "0700";
          StateDirectoryMode = "0700";
          LogsDirectoryMode = "0700";
          UMask = "0077";
          PrivateTmp = lib.mkDefault true;
          # Reset the packaged unit's ambient set, which includes NET_ADMIN.
          AmbientCapabilities = [ "" "CAP_NET_BIND_SERVICE" ];
          CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
          ProtectKernelTunables = lib.mkDefault true;
          ProtectKernelModules = lib.mkDefault true;
          ProtectKernelLogs = lib.mkDefault true;
          ProtectControlGroups = lib.mkDefault true;
          ProtectClock = lib.mkDefault true;
          ProtectHostname = lib.mkDefault true;
          ProtectProc = lib.mkDefault "invisible";
          RestrictNamespaces = lib.mkDefault true;
          RestrictSUIDSGID = lib.mkDefault true;
          RestrictRealtime = lib.mkDefault true;
          LockPersonality = lib.mkDefault true;
          MemoryDenyWriteExecute = lib.mkDefault true;
          SystemCallArchitectures = lib.mkDefault "native";
          SystemCallFilter = [ "@system-service" ];
          RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        };
      };
    };
}
