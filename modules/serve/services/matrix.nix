/**
  Local Tuwunel Matrix service without public ingress policy.
*/
{ self, ... }:
{
  flake.modules.nixos.serve-matrix =
    { config, lib, ... }:
    let
      cfg = config.serve.matrix;
    in
    {
      options.serve.matrix = {
        enable = lib.mkEnableOption "the local Tuwunel Matrix service";

        serverName = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = "Matrix server name.";
        };

        address = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Local Tuwunel listener address.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 6167;
          description = "Local Tuwunel listener port.";
        };

        maxRequestSize = lib.mkOption {
          type = lib.types.ints.positive;
          default = self.lib.units.IEC.bytes.GiB 2;
          description = "Maximum Matrix request size in bytes.";
        };
      };

      config = lib.mkIf cfg.enable {
        services.matrix-tuwunel = {
          enable = true;
          settings.global = {
            server_name = cfg.serverName;
            address = [ cfg.address ];
            port = [ cfg.port ];
            allow_registration = false;
            allow_federation = true;
            allow_encryption = true;
            federate_admin_room = false;
            delete_rooms_after_leave = true;
            max_request_size = cfg.maxRequestSize;
          };
        };
      };
    };
}
