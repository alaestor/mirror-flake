{ lib, ... }:
let
  hostIdentityModule =
    { lib, ... }:
    {
      options.hostIdentity = {
        name = lib.mkOption {
          type = lib.types.nonEmptyStr;
          readOnly = true;
          description = "The canonical host and configuration name.";
        };

        description = lib.mkOption {
          type = lib.types.nonEmptyStr;
          readOnly = true;
          description = "A human-readable description of this host.";
        };

        primaryUser = lib.mkOption {
          type = lib.types.nonEmptyStr;
          readOnly = true;
          description = "The primary interactive user of this host.";
        };

        stateVersion = lib.mkOption {
          type = lib.types.nonEmptyStr;
          readOnly = true;
          description = "The compatibility state version shared with this host's user environments.";
        };
      };
    };
in
{
  config = {
    flake.lib.hostIdentityModule = hostIdentityModule;

    flake.modules.nixos.host-identity =
      { config, ... }:
      {
        imports = [ hostIdentityModule ];

        networking.hostName = config.hostIdentity.name;
      };

    flake.modules.nixOnDroid.host-identity =
      { config, lib, ... }:
      {
        imports = [ hostIdentityModule ];

        system.stateVersion = lib.mkDefault config.hostIdentity.stateVersion;
      };
  };
}
