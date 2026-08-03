/**
  Exports `flake.modules.nixos.ssh-client` and
  `flake.modules.homeManager.ssh-client`. The NixOS feature deploys the
  host-named client identity through Agenix when its ciphertext exists and
  otherwise warns without blocking bootstrap. The Home Manager feature enables
  the opinionated SSH program module and selects
  `~/.ssh/id_ed25519_<lowercase-hostname>` for registered host user
  environments. Consumers may prepend higher-priority identities through
  `ssh-client.identityFiles`; an empty list disables identity selection.
*/
{ inputs, self, ... }:
{
  flake.modules.nixos.ssh-client =
    {
      config,
      lib,
      ...
    }:
    let
      hostName = lib.toLower config.hostIdentity.name;
      username = config.hostIdentity.primaryUser;
      user = config.users.users.${username};
      secret = self.secrets.sshClient hostName;
      secretName = "ssh-client-${hostName}-identity";
    in
    {
      imports = [ inputs.self.modules.nixos.agenix-host-identity ];

      warnings = lib.optional (!secret.exists) ''
        ssh-client: ${secret.subpath} is absent; skipping client-key deployment for ${hostName}
      '';

      age.secrets = lib.mkIf secret.exists {
        ${secretName} = {
          inherit (secret) file;
          path = "${user.home}/.ssh/${secret.fileName}";
          owner = username;
          group = user.group;
          mode = "0400";
        };
      };
    };

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
