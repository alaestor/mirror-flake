/**
  Exports `flake.modules.homeManager.ssh-client`. Importing it enables the
  opinionated SSH program module and selects
  `~/.ssh/id_ed25519_<lowercase-hostname>` for registered host user
  environments. Consumers may prepend higher-priority identities through
  `ssh-client.identityFiles`; an empty list disables identity selection.
*/
{ inputs, ... }:
{
  # TODO(droid): ssh-client for droid?
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
      defaultIdentityFiles =
        if options ? userEnvironment then
          [ "~/.ssh/id_ed25519_${lib.toLower config.userEnvironment.hostName}" ]
        else
          [ ];
    in
    {
      imports = [ inputs.self.modules.homeManager.ssh ];

      options.ssh-client.identityFiles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = defaultIdentityFiles;
        defaultText = lib.literalExpression ''[ "~/.ssh/id_ed25519_\${lib.toLower config.userEnvironment.hostName}" ]'';
        example = [
          "~/.ssh/ssh_sk"
          "~/.ssh/id_ed25519_apc"
        ];
        description = "Identity files used by the default SSH client host block, in priority order.";
      };

      config = {
        programs.ssh =
          lib.mkIf (cfg.identityFiles != [ ]) (
            if hasStructuredSettings then
              {
                settings."*" = {
                  IdentityFile = cfg.identityFiles;
                  IdentitiesOnly = true;
                };
              }
            else
              {
                matchBlocks."*" = {
                  identityFile = cfg.identityFiles;
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
