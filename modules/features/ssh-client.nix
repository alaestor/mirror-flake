{ inputs, ... }:
{
  flake.modules.homeManager.ssh-client =
    {
      config,
      lib,
      options,
      ...
    }:
    let
      cfg = config.ssh-client;
      hasStructuredSettings = options.programs.ssh ? settings;
    in
    {
      imports = [ inputs.self.modules.homeManager.ssh ];

      options.ssh-client.identityFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "~/.ssh/id_ed25519";
        description = "Identity file used by the default SSH client host block.";
      };

      config = {
        programs.ssh =
          lib.mkIf (cfg.identityFile != null) (
            if hasStructuredSettings then
              {
                settings."*" = {
                  IdentityFile = cfg.identityFile;
                  IdentitiesOnly = true;
                };
              }
            else
              {
                matchBlocks."*" = {
                  identityFile = cfg.identityFile;
                  identitiesOnly = true;
                };
              }
          );

        programs.nushell.extraConfig = lib.mkAfter ''
          # Deliberately bypass host-key verification for an ad-hoc connection.
          def sshu [...args] {
            ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" ...$args
          }
        '';
      };
    };
}
