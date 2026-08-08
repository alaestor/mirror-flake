/**
  Exports `flake.modules.nixos.ssh-client`, the dormant Home Manager option
  interface `ssh-known-hosts`, and `flake.modules.homeManager.ssh-client`.
  The NixOS feature deploys the
  host-named client identity through Agenix when its ciphertext exists and
  otherwise warns without blocking bootstrap. The Home Manager feature enables
  the opinionated SSH program module and selects
  `~/.ssh/id_ed25519_<lowercase-hostname>` for registered host user
  environments. Consumers may prepend higher-priority identities through
  `ssh-client.identityFiles`; an empty list disables identity selection.
  `ssh-client.knownHosts` declares SSH host keys grouped by DNS domain, and
  accepts additive entries from compositions such as `tailnet-client`.
  Repository-managed common and tailnet host keys are enabled independently
  through `knowCommonHosts` and `knowTailnetHosts`.
*/
{ inputs, self, ... }:
{
  flake.modules.homeManager.ssh-known-hosts = { lib, ... }: {
    # The interface may arrive through both ssh-client and a contributing composition.
    key = "flake.modules.homeManager.ssh-known-hosts";

    options.ssh-client = {
      knowCommonHosts = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to include the repository-managed common SSH host keys.";
      };

      knowTailnetHosts = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether tailnet compositions may contribute repository-managed SSH host keys.";
      };

      knownHosts = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf (lib.types.listOf lib.types.str));
        default = { };
        example = {
          "example.org"."git.example.org" = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeExampleHostKey"
          ];
        };
        description = ''
          SSH host public keys grouped by DNS domain, then hostname. Each key
          is the `type base64-data` portion of a known-host entry. Definitions
          merge additively, so compositions may contribute further domains or
          host keys.
        '';
      };
    };
  };

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
      defaultKnownHosts = import (self.data.path "features/ssh-client/known-hosts.nix") { inherit lib; };
      renderKnownHosts =
        lib.concatMapStringsSep "\n\n" (
          domain:
          let
            hosts = cfg.knownHosts.${domain};
            hostLines = lib.concatMap (
              hostName:
              map (publicKey: "${hostName} ${publicKey}") hosts.${hostName}
            ) (lib.sort builtins.lessThan (builtins.attrNames hosts));
          in
          "# ${domain}\n${lib.concatStringsSep "\n" hostLines}"
        ) (lib.sort builtins.lessThan (builtins.attrNames cfg.knownHosts)) + "\n";
      defaultIdentityFiles =
        if options ? userEnvironment then
          [ "~/.ssh/id_ed25519_${lib.toLower config.userEnvironment.hostName}" ]
        else
          [ ];
    in
    {
      imports = [
        inputs.self.modules.homeManager.ssh
        inputs.self.modules.homeManager.ssh-known-hosts
      ];

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
        ssh-client.knownHosts = lib.mkIf cfg.knowCommonHosts defaultKnownHosts;

        home.file.".ssh/known_hosts".text = renderKnownHosts;

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
