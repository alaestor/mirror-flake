{ inputs, ... }:
{
  flake.modules.homeManager.ssh-client =
    { config, lib, ... }:
    let
      cfg = config.ssh-client;
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
        programs.ssh.settings."*" = lib.mkIf (cfg.identityFile != null) {
          IdentityFile = cfg.identityFile;
          IdentitiesOnly = true;
        };

        programs.nushell.extraConfig = lib.mkAfter ''
          # Deliberately bypass host-key verification for an ad-hoc connection.
          def sshu [...args] {
            ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" ...$args
          }
        '';
      };
    };
}
